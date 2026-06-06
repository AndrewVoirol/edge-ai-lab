import XCTest
import LiteRTLM

#if os(iOS)
@testable import GemmaEdgeGallery_iOS
#elseif os(macOS)
@testable import GemmaEdgeGallery_macOS
#endif

final class ToolCallingIntegrationTests: XCTestCase {

    func testCalculatorToolNotifiesTracker() async throws {
        let expectation = XCTestExpectation(description: "Tracker notified by CalculatorTool")
        ToolExecutionTracker.shared.registerCallback { event in
            XCTAssertEqual(event.toolName, "calculate")
            XCTAssertTrue(event.succeeded)
            XCTAssertTrue(event.arguments.contains("2 + 2"))
            XCTAssertTrue(event.result.contains("4"))
            expectation.fulfill()
        }
        defer { ToolExecutionTracker.shared.clearCallback() }
        
        var tool = CalculatorTool()
        tool.expression = "2 + 2"
        _ = try await tool.run()
        
        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func testUnitConverterToolNotifiesTracker() async throws {
        let expectation = XCTestExpectation(description: "Tracker notified by UnitConverterTool")
        ToolExecutionTracker.shared.registerCallback { event in
            XCTAssertEqual(event.toolName, "convert_units")
            XCTAssertTrue(event.succeeded)
            expectation.fulfill()
        }
        defer { ToolExecutionTracker.shared.clearCallback() }
        
        var tool = UnitConverterTool()
        tool.value = 100
        tool.fromUnit = "celsius"
        tool.toUnit = "fahrenheit"
        _ = try await tool.run()
        
        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func testTextAnalyzerToolNotifiesTracker() async throws {
        let expectation = XCTestExpectation(description: "Tracker notified by TextAnalyzerTool")
        ToolExecutionTracker.shared.registerCallback { event in
            XCTAssertEqual(event.toolName, "analyze_text")
            XCTAssertTrue(event.succeeded)
            expectation.fulfill()
        }
        defer { ToolExecutionTracker.shared.clearCallback() }
        
        var tool = TextAnalyzerTool()
        tool.text = "Hello world from integration tests."
        _ = try await tool.run()
        
        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func testSystemHealthToolNotifiesTracker() async throws {
        let expectation = XCTestExpectation(description: "Tracker notified by SystemHealthTool")
        ToolExecutionTracker.shared.registerCallback { event in
            XCTAssertEqual(event.toolName, "get_system_health")
            XCTAssertTrue(event.succeeded)
            expectation.fulfill()
        }
        defer { ToolExecutionTracker.shared.clearCallback() }
        
        let tool = SystemHealthTool()
        _ = try await tool.run()
        
        await fulfillment(of: [expectation], timeout: 2.0)
    }

    @MainActor
    func testToolExecutionTrackerViewModelIntegration() async throws {
        let engine = MockInstrumentedEngine()
        try await engine.initialize(
            modelPath: "",
            useGPU: false,
            cacheDir: "",
            flags: ExperimentalFlagsState(enableBenchmark: false, enableSpeculativeDecoding: nil, enableConversationConstrainedDecoding: false, visualTokenBudget: nil),
            samplerConfig: nil,
            systemMessage: nil,
            tools: nil
        )
        let viewModel = ConversationViewModel(engine: engine)
        
        // Simulate a tool call being triggered while generateText is executing.
        // We set chunkDelay on MockInstrumentedEngine to ensure the stream stays active
        // while we inject the tool call notification.
        engine.chunkDelay = 0.1
        
        let task = Task {
            await viewModel.generateText()
        }
        
        // Wait briefly for the stream to begin and view model to start observing
        try await Task.sleep(for: .seconds(0.05))
        
        let event = ToolCallEvent(
            toolName: "calculate",
            arguments: "{\"expression\": \"2 + 2\"}",
            result: "{\"result\": 4}",
            durationMs: 1.0,
            timestamp: Date(),
            succeeded: true
        )
        ToolExecutionTracker.shared.notify(event)
        
        // Await the generation task to complete
        _ = await task.result
        
        // Verify view model recorded the event
        XCTAssertEqual(viewModel.toolCallEvents.count, 1)
        XCTAssertEqual(viewModel.toolCallEvents.first?.toolName, "calculate")
    }
}
