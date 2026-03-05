import Combine
import Foundation

@MainActor
final class QueueViewModel: ObservableObject {
    @Published var selectedJobIDs = Set<UUID>()
    @Published var renameConfiguration = BatchRenameConfiguration()
    @Published var draftOptions: ConversionOptions
    @Published var isAdvancedExpanded = false
    @Published var hasInvalidCustomResolution = false
    @Published var hasInvalidCustomFPS = false

    let queueStore: JobQueueStore

    init(queueStore: JobQueueStore) {
        self.queueStore = queueStore
        self.draftOptions = queueStore.optionsForSelection(nil)
    }

    var activePreset: ConversionPreset {
        ConversionPreset.builtIns.first(where: { $0.name == draftOptions.presetName }) ?? ConversionPreset.builtIns[0]
    }

    var renamePreview: [UUID: String] {
        FilenameRenamer.preview(for: queueStore.jobs, configuration: renameConfiguration)
    }

    var selectedJobs: [VideoJob] {
        queueStore.jobs.filter { selectedJobIDs.contains($0.id) }
    }

    var isAdvancedModified: Bool {
        draftOptions.videoBitrateKbps != nil ||
        draftOptions.subtitleAttachments.contains(where: { $0.languageCode != "eng" })
    }

    var hasInvalidCustomInputs: Bool {
        hasInvalidCustomResolution || hasInvalidCustomFPS
    }

    func refreshDraftOptions() {
        draftOptions = queueStore.optionsForSelection(selectedJobIDs)
    }

    func applyDraftOptions() {
        queueStore.applyOptions(draftOptions, to: selectedJobIDs)
    }

    func selectPreset(_ preset: ConversionPreset) {
        draftOptions = queueStore.applyPreset(preset, to: selectedJobIDs)
    }

    func updateOptions(_ mutate: (inout ConversionOptions) -> Void) {
        mutate(&draftOptions)
        applyDraftOptions()
    }

    func applyRenamePreview() {
        queueStore.applyBatchRename(configuration: renameConfiguration)
    }

    func removeSelectedJobs() {
        queueStore.remove(jobIDs: selectedJobIDs)
        selectedJobIDs.removeAll()
        refreshDraftOptions()
    }

    func setCustomValidation(resolutionValid: Bool?, fpsValid: Bool?) {
        if let resolutionValid {
            hasInvalidCustomResolution = !resolutionValid
        }
        if let fpsValid {
            hasInvalidCustomFPS = !fpsValid
        }
    }
}
