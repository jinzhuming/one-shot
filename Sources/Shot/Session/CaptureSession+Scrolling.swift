import AppKit
import ShotKit

@MainActor
extension CaptureSession {
    func startScrolling(_ selection: RegionSelection) {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == selection.displayID }) else {
            fail(CaptureError.noDisplay)
            return
        }
        let targetWindow = overlay.windowCatalog.hitTest(
            CGPoint(x: selection.rect.midX, y: selection.rect.midY)
        )
        let coordinator = ScrollCaptureCoordinator(
            captureService: captureService,
            catalog: overlay.windowCatalog,
            expectedWindow: targetWindow,
            onProgress: { [weak self] progress in
                self?.overlay.updateScrollingCapture(progress)
            }
        )
        scrollCaptureCoordinator = coordinator
        overlay.beginScrolling(on: screen) { [weak self] in
            self?.finishScrolling()
        }
        runCapture(timeout: nil) { [weak self, coordinator] operation in
            guard let self else { return }
            do {
                let result = try await coordinator.run(selection: selection)
                try Task.checkCancellation()
                guard self.isCurrent(operation) else { return }
                self.scrollCaptureCoordinator = nil
                await self.handle(result, operation: operation)
            } catch is CancellationError {
                return
            } catch {
                self.scrollCaptureCoordinator = nil
                self.fail(error, operation: operation)
            }
        }
    }

}
