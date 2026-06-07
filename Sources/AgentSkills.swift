import Foundation
import LiteRTLM
import CoreLocation
import MapKit

// MARK: - WikipediaSkillTool

/// Fact-grounding tool. Searches Wikipedia API for a query and returns a structured JSON summary.
/// Gracefully falls back to an offline/error response on connection failure.
public struct WikipediaSkillTool: Tool {
    public static let name = "wikipedia_search"
    public static let description = "Search Wikipedia for a summary of a given topic"

    @ToolParam(description: "The search query or topic to search on Wikipedia, e.g. 'James Webb Space Telescope'")
    public var query: String

    public init() {}

    public func run() async throws -> Any {
        let startTime = CFAbsoluteTimeGetCurrent()
        let argumentsDict = ["query": query]
        var resultString = ""
        defer {
            let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            let succeeded = !resultString.isEmpty && !resultString.contains("\"error\"")
            let event = ToolCallEvent(
                toolName: Self.name,
                arguments: jsonString(from: argumentsDict),
                result: resultString,
                durationMs: duration,
                timestamp: Date(),
                succeeded: succeeded
            )
            ToolExecutionTracker.shared.notify(event)
        }

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            resultString = jsonString(from: [
                "type": "wikipedia",
                "error": "Query cannot be empty",
                "query": query
            ])
            return resultString
        }

        do {
            // Step 1: Search Wikipedia for the topic to get the best-matching title.
            guard let searchUrl = URL(string: "https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&format=json&utf8=") else {
                throw NSError(domain: "WikipediaSkillTool", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }

            let (searchData, _) = try await URLSession.shared.data(from: searchUrl)
            guard let searchJson = try JSONSerialization.jsonObject(with: searchData) as? [String: Any],
                  let queryObj = searchJson["query"] as? [String: Any],
                  let searchResults = queryObj["search"] as? [[String: Any]],
                  let firstResult = searchResults.first,
                  let pageTitle = firstResult["title"] as? String else {
                resultString = jsonString(from: [
                    "type": "wikipedia",
                    "error": "No Wikipedia article found for search query.",
                    "query": query
                ])
                return resultString
            }

            // Step 2: Fetch the summary of that page title.
            guard let summaryUrl = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(pageTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")") else {
                throw NSError(domain: "WikipediaSkillTool", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid summary URL"])
            }

            let (summaryData, _) = try await URLSession.shared.data(from: summaryUrl)
            guard let summaryJson = try JSONSerialization.jsonObject(with: summaryData) as? [String: Any] else {
                throw NSError(domain: "WikipediaSkillTool", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid summary JSON response"])
            }

            let title = summaryJson["title"] as? String ?? pageTitle
            let extract = summaryJson["extract"] as? String ?? ""
            let contentUrls = summaryJson["content_urls"] as? [String: Any]
            let desktop = contentUrls?["desktop"] as? [String: Any]
            let pageUrl = desktop?["page"] as? String ?? "https://en.wikipedia.org/wiki/\(pageTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")"
            
            var thumbnailUrl: String? = nil
            if let thumbnail = summaryJson["thumbnail"] as? [String: Any],
               let source = thumbnail["source"] as? String {
                thumbnailUrl = source
            }

            var responseObj: [String: Any] = [
                "type": "wikipedia",
                "query": query,
                "title": title,
                "extract": extract,
                "url": pageUrl
            ]
            if let thumbnailUrl = thumbnailUrl {
                responseObj["thumbnail_url"] = thumbnailUrl
            }

            resultString = jsonString(from: responseObj)
            return resultString
        } catch {
            // Catch connection errors and fall back to graceful offline/error message.
            resultString = jsonString(from: [
                "type": "wikipedia",
                "error": "Offline or search failed: \(error.localizedDescription)",
                "query": query,
                "offline": true
            ])
            return resultString
        }
    }
}

// MARK: - MapSkillTool

/// Interactive location tool. Centering map on geocoded location.
public struct MapSkillTool: Tool {
    public static let name = "show_map"
    public static let description = "Display an interactive map centered on the specified location or coordinates"

    @ToolParam(description: "The address, city, landmark, or coordinates to display on the map, e.g. 'Paris, France' or '48.8584, 2.2945'")
    public var query: String

    public init() {}

    public func run() async throws -> Any {
        let startTime = CFAbsoluteTimeGetCurrent()
        let argumentsDict = ["query": query]
        var resultString = ""
        defer {
            let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            let succeeded = !resultString.isEmpty && !resultString.contains("\"error\"")
            let event = ToolCallEvent(
                toolName: Self.name,
                arguments: jsonString(from: argumentsDict),
                result: resultString,
                durationMs: duration,
                timestamp: Date(),
                succeeded: succeeded
            )
            ToolExecutionTracker.shared.notify(event)
        }

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            resultString = jsonString(from: [
                "type": "map",
                "error": "Location query cannot be empty",
                "query": query
            ])
            return resultString
        }

        // Try parsing coordinates directly (latitude, longitude)
        let coords = parseCoordinates(query)
        if let (lat, lon) = coords {
            resultString = jsonString(from: [
                "type": "map",
                "query": query,
                "latitude": lat,
                "longitude": lon,
                "title": "Coordinates",
                "subtitle": "\(lat), \(lon)"
            ])
            return resultString
        }

        // Perform geocoding using MapKit (MKLocalSearch)
        do {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            let search = MKLocalSearch(request: request)
            let response = try await search.start()

            guard let firstItem = response.mapItems.first else {
                throw NSError(domain: "MapSkillTool", code: -1, userInfo: [NSLocalizedDescriptionKey: "No location found"])
            }

            let pm = firstItem.value(forKey: "placemark") as? CLPlacemark
            let lat = pm?.location?.coordinate.latitude ?? 0
            let lon = pm?.location?.coordinate.longitude ?? 0
            let name = firstItem.name ?? query
            let locality = pm?.locality
            let country = pm?.country
            var subtitle = ""
            if let locality = locality, let country = country {
                subtitle = "\(locality), \(country)"
            } else {
                subtitle = country ?? locality ?? ""
            }

            resultString = jsonString(from: [
                "type": "map",
                "query": query,
                "latitude": lat,
                "longitude": lon,
                "title": name,
                "subtitle": subtitle
            ])
            return resultString
        } catch {
            resultString = jsonString(from: [
                "type": "map",
                "error": "Could not find location: \(error.localizedDescription)",
                "query": query
            ])
            return resultString
        }
    }

    private func parseCoordinates(_ str: String) -> (Double, Double)? {
        let parts = str.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]) else {
            return nil
        }
        guard lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180 else {
            return nil
        }
        return (lat, lon)
    }
}


