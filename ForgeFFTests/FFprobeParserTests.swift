import XCTest
@testable import ForgeFF

final class FFprobeParserTests: XCTestCase {
    func testParseFFprobeJSONPayload() throws {
        let json = """
        {
          "format": {
            "filename": "/tmp/sample.mov",
            "format_name": "mov,mp4,m4a,3gp,3g2,mj2",
            "format_long_name": "QuickTime / MOV",
            "duration": "42.500000",
            "size": "12345678",
            "bit_rate": "2320000"
          },
          "streams": [
            {
              "index": 0,
              "codec_name": "hevc",
              "codec_long_name": "H.265 / HEVC",
              "codec_type": "video",
              "width": 3840,
              "height": 2160,
              "avg_frame_rate": "24000/1001",
              "color_transfer": "smpte2084"
            },
            {
              "index": 1,
              "codec_name": "aac",
              "codec_long_name": "AAC",
              "codec_type": "audio",
              "channel_layout": "5.1"
            }
          ],
          "chapters": [
            {
              "id": 0,
              "start_time": "0.0",
              "end_time": "21.0",
              "tags": {
                "title": "Intro"
              }
            }
          ]
        }
        """

        let metadata = try FFprobeService.parse(jsonData: Data(json.utf8))

        XCTAssertEqual(metadata.durationSeconds ?? 0, 42.5, accuracy: 0.001)
        XCTAssertEqual(metadata.videoStream?.width, 3840)
        XCTAssertEqual(metadata.audioStreams.count, 1)
        XCTAssertTrue(metadata.isHDR)
        XCTAssertEqual(metadata.chapters.first?.chapterTitle, "Intro")
    }
}
