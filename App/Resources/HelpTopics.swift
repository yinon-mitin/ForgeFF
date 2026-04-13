import AppKit
import SwiftUI

enum HelpTopic: Hashable {
    case presets
    case outputFolder
    case overwrite
    case container
    case videoCodec
    case quality
    case encoderOptions
    case resolution
    case resolutionCustomSize
    case fps
    case fpsCustom
    case audio
    case audioLocked
    case subtitles
    case moreSettings
    case audioBitrate
    case audioChannels
    case cleanup
    case webOptimization
    case externalAudio
    case hdrToSDR
    case toneMapMethod
    case rename
    case renameFields
    case advanced
    case customFFmpegCommand
}

struct HelpTopicContent {
    let title: String
    let bullets: [String]
}

extension HelpTopic {
    var content: HelpTopicContent {
        switch self {
        case .presets:
            return HelpTopicContent(
                title: "Presets",
                bullets: [
                    "Start here when you want a strong default without opening advanced controls.",
                    "Built-in presets pick a practical container, codec, quality, and speed mix for you.",
                    "Manual changes mark the preset as modified only while the effective settings still differ."
                ]
            )
        case .outputFolder:
            return HelpTopicContent(
                title: "Output Folder",
                bullets: [
                    "Choose or drop a folder for new exports.",
                    "Leave the default empty to save beside each source file.",
                    "Use the selection override when only some queue items need a different destination."
                ]
            )
        case .overwrite:
            return HelpTopicContent(
                title: "Overwrite",
                bullets: [
                    "Turn this on only when replacing old exports is safe.",
                    "When off, ForgeFF keeps existing files and adds a number to the new filename."
                ]
            )
        case .container:
            return HelpTopicContent(
                title: "Container",
                bullets: [
                    "MP4 is the safest general-purpose choice.",
                    "MOV is better for editing workflows, and MKV is more flexible for mixed streams.",
                    "The container limits which video codecs are available."
                ]
            )
        case .videoCodec:
            return HelpTopicContent(
                title: "Video Codec",
                bullets: [
                    "H.264 plays almost everywhere, HEVC is smaller on newer devices, and ProRes is for editing.",
                    "AV1 and VP9 can save space, but they need FFmpeg support and usually take longer."
                ]
            )
        case .quality:
            return HelpTopicContent(
                title: "Quality",
                bullets: [
                    "Smaller favors size, Balanced is the everyday default, and Better keeps more detail.",
                    "Use Better when the output will be archived, edited again, or shown on larger screens."
                ]
            )
        case .encoderOptions:
            return HelpTopicContent(
                title: "Encoder Options",
                bullets: [
                    "Auto picks a sensible speed from your codec and quality choice.",
                    "Faster modes finish sooner but usually need more bitrate for the same visual result.",
                    "Use Slow only when size or quality matters more than time."
                ]
            )
        case .resolution:
            return HelpTopicContent(
                title: "Resolution",
                bullets: [
                    "Keep preserves the source size, while presets scale down to common targets.",
                    "Use a smaller size to reduce file size and make playback easier on older devices."
                ]
            )
        case .resolutionCustomSize:
            return HelpTopicContent(
                title: "Custom Size",
                bullets: [
                    "Enter the maximum output width and height in pixels.",
                    "ForgeFF keeps the source aspect ratio, so the final output may be smaller than both values."
                ]
            )
        case .fps:
            return HelpTopicContent(
                title: "FPS",
                bullets: [
                    "Keep preserves the source frame rate.",
                    "Lower frame rates can save space, while higher frame rates are useful only when the source already needs them."
                ]
            )
        case .fpsCustom:
            return HelpTopicContent(
                title: "Custom FPS",
                bullets: [
                    "Use a specific frame rate only when a delivery spec requires it.",
                    "Example: enter 29.97 for broadcast-style NTSC output."
                ]
            )
        case .audio:
            return HelpTopicContent(
                title: "Audio",
                bullets: [
                    "Keep copies the original audio without re-encoding it.",
                    "Choose AAC for general playback and MP3 for older players or voice-only exports.",
                    "When audio is copied, bitrate and channel controls stay locked because nothing is being re-encoded."
                ]
            )
        case .audioLocked:
            return HelpTopicContent(
                title: "Locked While Copying Audio",
                bullets: [
                    "Audio bitrate and channel settings work only when ForgeFF is re-encoding the audio stream.",
                    "Switch Audio from Keep to AAC or MP3 if you need to change those values."
                ]
            )
        case .subtitles:
            return HelpTopicContent(
                title: "Subtitles",
                bullets: [
                    "Keep preserves embedded subtitles when the output supports them.",
                    "Remove drops subtitle streams, and Add External lets you mux in one or more subtitle files.",
                    "Each added subtitle track keeps its own language code and order."
                ]
            )
        case .moreSettings:
            return HelpTopicContent(
                title: "More Settings",
                bullets: [
                    "Open this when you need finer control over format, video, audio, subtitles, cleanup, or advanced tools.",
                    "Leave it collapsed for a simpler beginner workflow."
                ]
            )
        case .audioBitrate:
            return HelpTopicContent(
                title: "Audio Bitrate",
                bullets: [
                    "Higher bitrate keeps more detail but makes files larger.",
                    "Auto is usually fine for AAC and MP3 unless you have a delivery target."
                ]
            )
        case .audioChannels:
            return HelpTopicContent(
                title: "Audio Channels",
                bullets: [
                    "Keep preserves the source layout when audio is re-encoded.",
                    "Force Stereo for widest compatibility, or 5.1/7.1 only when the source and destination need surround."
                ]
            )
        case .cleanup:
            return HelpTopicContent(
                title: "Cleanup",
                bullets: [
                    "Remove metadata when you want a cleaner export without inherited tags.",
                    "Remove chapters when the destination player or workflow does not need them."
                ]
            )
        case .webOptimization:
            return HelpTopicContent(
                title: "Web Optimization",
                bullets: [
                    "Use this for MP4 or MOV files that will stream from the web.",
                    "It moves playback metadata to the start so video can begin sooner.",
                    "MKV ignores this option."
                ]
            )
        case .externalAudio:
            return HelpTopicContent(
                title: "External Audio",
                bullets: [
                    "Replace the source audio with one or more separate files such as WAV, AAC, MP3, or FLAC.",
                    "Use this for voice-over, cleaned audio, alternate languages, or commentary tracks.",
                    "Track order matters, and every file must stay readable before you start the queue."
                ]
            )
        case .hdrToSDR:
            return HelpTopicContent(
                title: "HDR to SDR",
                bullets: [
                    "Use this when an HDR source needs a safer SDR export for standard displays.",
                    "Leave it off when you want to preserve HDR output."
                ]
            )
        case .toneMapMethod:
            return HelpTopicContent(
                title: "Tone Map Method",
                bullets: [
                    "This changes how bright HDR highlights are compressed into SDR.",
                    "Hable is a good default, and Reinhard can look gentler on highlights."
                ]
            )
        case .rename:
            return HelpTopicContent(
                title: "Rename",
                bullets: [
                    "Use batch rename rules when many queue items need the same filename cleanup.",
                    "Preview shows how the first queue item will change before you apply it."
                ]
            )
        case .renameFields:
            return HelpTopicContent(
                title: "Rename Fields",
                bullets: [
                    "Prefix adds text to the front, Suffix adds text to the end, and Replace swaps one phrase for another.",
                    "Sanitize removes characters that are unsafe in filenames."
                ]
            )
        case .advanced:
            return HelpTopicContent(
                title: "Advanced",
                bullets: [
                    "Open this only when you need binary overrides, bitrate overrides, subtitle track language codes, or a custom FFmpeg template.",
                    "Most conversions should work without touching anything here."
                ]
            )
        case .customFFmpegCommand:
            return HelpTopicContent(
                title: "Custom FFmpeg Command",
                bullets: [
                    "This overrides ForgeFF's generated command for the selected queue items.",
                    "You must include both {input} and {output} placeholders.",
                    "Turning the switch off keeps the stored template, but the override stays inactive.",
                    "Use it only when ForgeFF's normal options cannot express the command you need."
                ]
            )
        }
    }
}

struct HelpPopoverButton: View {
    let topic: HelpTopic

    @State private var isPresented = false
    @State private var previousFirstResponder: NSResponder?
    @State private var previousWindowNumber: Int?

    var body: some View {
        Button {
            if isPresented {
                isPresented = false
            } else {
                captureFocusContext()
                isPresented = true
            }
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("Show help for \(topic.content.title)")
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            HelpTopicPopover(topic: topic)
        }
        .onChange(of: isPresented) { isOpen in
            if !isOpen {
                restoreFocusContext()
            }
        }
    }

    private func captureFocusContext() {
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        previousWindowNumber = window?.windowNumber
        previousFirstResponder = window?.firstResponder
    }

    private func restoreFocusContext() {
        guard let windowNumber = previousWindowNumber,
              let window = NSApp.window(withWindowNumber: windowNumber),
              let previousFirstResponder else {
            previousWindowNumber = nil
            previousFirstResponder = nil
            return
        }

        DispatchQueue.main.async {
            window.makeFirstResponder(previousFirstResponder)
        }

        previousWindowNumber = nil
        self.previousFirstResponder = nil
    }
}

private struct HelpTopicPopover: View {
    let topic: HelpTopic

    var body: some View {
        let content = topic.content
        VStack(alignment: .leading, spacing: 10) {
            Text(content.title)
                .font(.headline)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(content.bullets.enumerated()), id: \.offset) { _, bullet in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .font(.callout.weight(.semibold))
                            Text(bullet)
                                .lineLimit(nil)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxHeight: 240)
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
    }
}
