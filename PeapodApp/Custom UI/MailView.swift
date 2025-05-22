//
//  MailView.swift
//  PeapodApp
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

        // Attach ALL log files (current + rotated)
        let allLogFiles = LogManager.shared.getAllLogFiles()
        for (index, logFileURL) in allLogFiles.enumerated() {
            if let data = try? Data(contentsOf: logFileURL) {
                let fileName = index == 0 ? "peapod-logs-current.txt" : "peapod-logs-\(index).txt"
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
    
    // Add log storage info for debugging
    let logSize = LogManager.shared.getTotalLogSize()

    return """
    Please describe the issue you're experiencing:
    
    
    ------
    App Version: \(appVersion) (\(buildNumber))
    Device: \(deviceModel)
    OS: \(systemName) \(systemVersion)
    Log Storage: \(logSize)
    """
}

