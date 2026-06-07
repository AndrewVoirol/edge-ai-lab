import SwiftUI
import MapKit

// MARK: - Streaming Indicator

/// Animated typing indicator shown while the assistant is generating.
/// Three dots with staggered pulse animations in the accent teal color.
struct StreamingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(AppColors.accentTeal.opacity(0.7))
                    .frame(width: 7, height: 7)
                    .scaleEffect(isAnimating ? 1.0 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever()
                        .delay(Double(i) * 0.15),
                        value: isAnimating
                    )
            }
        }
        .onAppear { isAnimating = true }
        .accessibilityIdentifier("streamingIndicator")
    }
}

// MARK: - Wikipedia Summary Card

struct WikipediaSummaryCard: View {
    let title: String
    let extract: String
    let urlString: String
    let thumbnailUrlString: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .top, spacing: AppSpacing.md) {
                if let urlStr = thumbnailUrlString, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                        default:
                            Image(systemName: "book.pages")
                                .font(.largeTitle)
                                .frame(width: 80, height: 80)
                                .background(AppColors.backgroundSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                        }
                    }
                } else {
                    Image(systemName: "book.pages.fill")
                        .font(.largeTitle)
                        .foregroundStyle(AppColors.accentTeal)
                        .frame(width: 80, height: 80)
                        .background(AppColors.accentTeal.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(2)
                        
                        Spacer()
                        
                        Image(systemName: "arrow.up.forward.app")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    
                    Text(extract)
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(4)
                }
            }
            
            if let url = URL(string: urlString) {
                Link(destination: url) {
                    HStack {
                        Text("Read full Wikipedia article")
                            .font(.caption)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundStyle(AppColors.accentTeal)
                }
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.assistantBubble.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }
}

// MARK: - Simple Map View

struct SimpleMapView: View {
    let latitude: Double
    let longitude: Double
    let title: String
    let subtitle: String?

    @State private var position: MapCameraPosition

    init(latitude: Double, longitude: Double, title: String, subtitle: String?) {
        self.latitude = latitude
        self.longitude = longitude
        self.title = title
        self.subtitle = subtitle
        
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let span = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        _position = State(initialValue: .region(MKCoordinateRegion(center: center, span: span)))
    }

    var body: some View {
        Map(position: $position) {
            Marker(title, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }
}


// MARK: - Code Block View

struct CodeBlockView: View {
    let code: String
    let language: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                if let language = language, !language.isEmpty {
                    Text(language.lowercased())
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                        .foregroundStyle(AppColors.textSecondary)
                } else {
                    Text("code")
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                        .foregroundStyle(AppColors.textSecondary)
                }
                
                Spacer()
                
                Button {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    #else
                    UIPasteboard.general.string = code
                    #endif
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Copy Code")
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.xs)
            .background(Color.black.opacity(0.3))
            
            // Code Content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(AppColors.textPrimary)
                    .textSelection(.enabled)
                    .padding(AppSpacing.md)
            }
        }
        .background(AppColors.backgroundTertiary.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.sm)
                .stroke(AppColors.border, lineWidth: 0.5)
        )
    }
}
