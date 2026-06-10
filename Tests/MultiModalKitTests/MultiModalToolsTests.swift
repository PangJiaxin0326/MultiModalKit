import AIToolKit
import Foundation
import FoundationModels
import Testing
@testable import MultiModalKit

@Suite struct MultiModalToolsTests {
    @Test func registerAllRegistersEveryTool() async {
        let registry = ToolRegistry()
        await MultiModalTools.registerAll(in: registry)
        let names = await registry.registeredNames()

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

    @Test func manifestSubsetsRegisteredTools() async {
        let registry = ToolRegistry()
        await MultiModalTools.registerAll(in: registry)

        let subset = await registry.manifest(for: ["speak_text", "import_photo"])
        #expect(subset.map(\.name) == ["import_photo", "speak_text"])

        let empty = await registry.manifest(for: [])
        #expect(empty.isEmpty)
    }

    @Test func importPhotoToolCopiesFileThroughRegistry() async throws {
        let registry = ToolRegistry()
        await registry.register(ImportPhotoTool())

        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmk-tools-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        let source = workDirectory.appendingPathComponent("sample.png")
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        try bytes.write(to: source)

        let input = ImportPhotoTool.Input(
            imagePath: source.path(percentEncoded: false)
        ).generatedContent.data()
        let outputData = try await registry.call(
            name: "import_photo",
            jsonArguments: input,
            context: ToolContext()
        )
        let output = try ImportPhotoTool.Output(GeneratedContent(data: outputData))

        #expect(output.byteCount == bytes.count)
        #expect(output.contentType == "public.png")
        #expect(FileManager.default.fileExists(atPath: output.importedPath))
        try? FileManager.default.removeItem(at: URL(filePath: output.importedPath))
    }

    @Test func invokingWithMissingRequiredFieldThrows() async {
        let registry = ToolRegistry()
        await registry.register(ImportPhotoTool())

        await #expect(throws: ToolRegistryError.self) {
            try await registry.call(
                name: "import_photo",
                jsonArguments: Data("{}".utf8),
                context: ToolContext()
            )
        }
    }
}
