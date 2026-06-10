import AIToolKit
import Foundation
import FoundationModels
import Testing
@testable import MultiModalKit

@Suite struct MultiModalToolsTests {
    @Test @MainActor func allExposesEveryTool() {
        let names = MultiModalTools.all().map(\.name)

        #expect(names == [
            "recognize_text",
            "speak_text",
            "transcribe_audio_file",
            "transcribe_speech",
            "import_photo",
            "record_audio",
            "capture_photo",
        ])
    }

    @Test func descriptorExposesNameDescriptionAndSchema() throws {
        let descriptor = RecognizeTextTool().descriptor

        #expect(descriptor.name == "recognize_text")
        #expect(descriptor.name == RecognizeTextTool.toolName)
        #expect(!descriptor.description.isEmpty)
        #expect(try descriptor.argumentsSchema.jsonString().contains("imagePath"))
        #expect(try descriptor.outputSchema?.jsonString().contains("fullText") == true)
    }

    @Test func recognizeTextSchemaRequiresImagePath() throws {
        let schema = try GeneratedContent(
            json: RecognizeTextTool.Input.generationSchema.jsonString()
        )
        let fields = try #require(schema.objectValue)
        #expect(fields["type"]?.stringValue == "object")
        #expect(fields["required"]?.allStrings == ["imagePath"])
    }

    @Test func importPhotoToolCopiesFile() async throws {
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmk-tools-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        let source = workDirectory.appendingPathComponent("sample.png")
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        try bytes.write(to: source)

        let input = ImportPhotoTool.Input(
            imagePath: source.path(percentEncoded: false)
        ).generatedContent
        let outputContent = try await WorkflowExecutor.callTool(ImportPhotoTool(), with: input)
        let output = try ImportPhotoTool.Output(outputContent)

        #expect(output.byteCount == bytes.count)
        #expect(output.contentType == "public.png")
        #expect(FileManager.default.fileExists(atPath: output.importedPath))
        try? FileManager.default.removeItem(at: URL(filePath: output.importedPath))
    }

    @Test func invokingWithMissingRequiredFieldThrows() async throws {
        await #expect(throws: GenericToolError.self) {
            try await WorkflowExecutor.callTool(
                ImportPhotoTool(),
                with: GeneratedContent(json: "{}")
            )
        }
    }
}
