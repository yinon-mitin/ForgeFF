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
        XCTAssertEqual(metadata.dynamicRangeDescription, "HDR (PQ)")
        XCTAssertEqual(metadata.chapters.first?.chapterTitle, "Intro")
    }

    func testParseFFprobeDetectsDolbyVisionFromSideData() throws {
        let json = """
        {
          "format": {
            "filename": "/tmp/dovi.mp4",
            "format_name": "mov,mp4,m4a,3gp,3g2,mj2",
            "format_long_name": "QuickTime / MOV",
            "duration": "12.000000",
            "size": "2345678",
            "bit_rate": "1820000"
          },
          "streams": [
            {
              "index": 0,
              "codec_name": "hevc",
              "codec_long_name": "H.265 / HEVC",
              "profile": "Main 10",
              "codec_type": "video",
              "width": 3840,
              "height": 2160,
              "avg_frame_rate": "24000/1001",
              "color_transfer": "smpte2084",
              "color_primaries": "bt2020",
              "color_space": "bt2020nc",
              "side_data_list": [
                {
                  "side_data_type": "DOVI configuration record",
                  "dv_profile": 8,
                  "dv_level": 6,
                  "rpu_present_flag": 1
                }
              ]
            }
          ]
        }
        """

        let metadata = try FFprobeService.parse(jsonData: Data(json.utf8))

        XCTAssertTrue(metadata.isHDR)
        XCTAssertEqual(metadata.dynamicRangeDescription, "Dolby Vision (Profile 8)")
    }

    func testParseFFprobeDetectsHLGTransfer() throws {
        let json = """
        {
          "format": {
            "filename": "/tmp/hlg.mkv",
            "format_name": "matroska,webm",
            "format_long_name": "Matroska / WebM",
            "duration": "8.000000",
            "size": "3456789",
            "bit_rate": "2820000"
          },
          "streams": [
            {
              "index": 0,
              "codec_name": "hevc",
              "codec_long_name": "H.265 / HEVC",
              "codec_type": "video",
              "width": 1920,
              "height": 1080,
              "avg_frame_rate": "25/1",
              "color_transfer": "arib-std-b67",
              "color_primaries": "bt2020",
              "color_space": "bt2020nc"
            }
          ]
        }
        """

        let metadata = try FFprobeService.parse(jsonData: Data(json.utf8))

        XCTAssertTrue(metadata.isHDR)
        XCTAssertEqual(metadata.dynamicRangeDescription, "HLG")
    }
}
