//
//  MailView.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-05-16.
//

import SwiftUI
import MessageUI

struct MailView: UIViewControllerRepresentable {
    let messageBody: String

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            controller.dismiss(animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.setToRecipients(["support@peapod.fm"])
        vc.setSubject("Peapod Feedback")
        vc.setMessageBody(messageBody, isHTML: false)

        // Attach ALL daily log files (up to 5 days)
        let allLogFiles = LogManager.shared.getAllLogFiles()
        for logFileURL in allLogFiles {
            if let data = try? Data(contentsOf: logFileURL) {
                // Use the actual filename for clarity (e.g., "peapod-2025-09-04.log")
                let fileName = logFileURL.lastPathComponent
                vc.addAttachmentData(data, mimeType: "text/plain", fileName: fileName)
            }
        }

        vc.mailComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
}

func generateSupportMessageBody() -> String {
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"

    let device = UIDevice.current
    let deviceModel = device.model
    let systemName = device.systemName
    let systemVersion = device.systemVersion
    
    // Add log info for debugging
    let logSize = LogManager.shared.getTotalLogSize()
    let logFiles = LogManager.shared.getAllLogFiles()
    let logCount = logFiles.count

    return """
    Please describe the issue you're experiencing:
    
    
    ------
    App Version: \(appVersion) (\(buildNumber))
    Device: \(deviceModel)
    OS: \(systemName) \(systemVersion)
    Log Files: \(logCount) files (\(logSize))
    """
}
