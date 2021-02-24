//
//  ViewController.swift
//  iNDEFExchange
//
//  Created by i9400506 on 2020/12/28.
//

import UIKit
import CoreNFC

class ViewController: UIViewController {
    
    private enum TagReadMode {
        case general
        case polling
    }
    
    @IBOutlet private weak var infoLabel: UILabel?
    
    private var ndefReaderSession: NFCNDEFReaderSession?
    
    private var tagReaderSession: NFCTagReaderSession?
    
    private let tagMode: TagReadMode = .polling
    
    private var currentInfo: String {
        return self.infoLabel?.text ?? ""
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    @IBAction private func writing() {
        guard NFCNDEFReaderSession.readingAvailable else {
            self.showAlertMessage()
            return
        }
        self.ndefReaderSession = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        self.ndefReaderSession?.alertMessage = "Hold your iPhone near a writable NFC tag to update."
        self.ndefReaderSession?.begin()
    }
    
    @IBAction private func scanning() {
        guard NFCNDEFReaderSession.readingAvailable else {
            self.showAlertMessage()
            return
        }
        self.tagReaderSession = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693, .iso18092], delegate: self, queue: nil)
        self.tagReaderSession?.alertMessage = "Hold your iPhone near an NFC ............tag."
        self.tagReaderSession?.begin()
    }
    
    private func showAlertMessage() {
        let alertController = UIAlertController(
            title: "Scanning Not Supported",
            message: "This device doesn't support tag scanning.",
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        self.present(alertController, animated: true, completion: nil)
    }
}

// MARK: - NFCNDEFReaderSessionDelegate
extension ViewController: NFCNDEFReaderSessionDelegate {
    
    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        // TODO:
    }
    
    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        // If necessary, you may handle the error. Note session is no longer valid.
        // You must create a new session to restart RF polling.
    }
    
    // MARK: iOS 11
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        // Do not add code in this function. This method isn't called
        // when you provide `reader(_:didDetect:)`.
    }
    
    // MARK: iOS 13
    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        
        guard let tag = tags.first else {
            session.restartPolling()
            return
        }
        
        guard tags.count == 1 else {
            session.alertMessage = "More than 1 tags found. Please present only 1 tag."
            self.tagRemovalDetect(tag)
            return
        }
        
        session.connect(to: tag) { (error) in
            guard error == nil else {
                session.restartPolling()
                return
            }
            tag.queryNDEFStatus { (status: NFCNDEFStatus, capacity: Int, error: Error?) in
                guard error == nil else {
                    session.invalidate(errorMessage: "Fail to determine NDEF status.  Please try again.")
                    return
                }
                switch status {
                case .notSupported:
                    session.invalidate(errorMessage: "Tag not support.")
                case .readOnly:
                    session.invalidate(errorMessage: "Tag is not writable.")
                case .readWrite:
                    guard let textPayload = NFCNDEFPayload.wellKnownTypeTextPayload(string: "Hello NFC Writter", locale: .init(identifier: "En")) else {
                        session.invalidate(errorMessage: "create playload error")
                        return
                    }
                    let message = NFCNDEFMessage(records: [textPayload])
                    // write就鎖定 tag就無法再利用
                    // tag.writeLock { (error) in }
                    tag.writeNDEF(message) { (error) in
                        guard error == nil else {
                            session.invalidate(errorMessage: "write NDEF error")
                            return
                        }
                        session.alertMessage = "update success"
                        session.invalidate()
                    }
                @unknown default:
                    session.invalidate(errorMessage: "status error")
                    return
                }
            }
        }
    }
    
    private func tagRemovalDetect(_ tag: NFCNDEFTag) {
        // In the tag removal procedure, you connect to the tag and query for
        // its availability. You restart RF polling when the tag becomes
        // unavailable; otherwise, wait for certain period of time and repeat
        // availability checking.
        self.ndefReaderSession?.connect(to: tag) { (error: Error?) in
            if error != nil || !tag.isAvailable {
                self.ndefReaderSession?.restartPolling()
                return
            }
            DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + .milliseconds(500), execute: {
                self.tagRemovalDetect(tag)
            })
        }
    }
}

// MARK: - NFCTagReaderSessionDelegate
extension ViewController: NFCTagReaderSessionDelegate {
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // If necessary, you may perform additional operations on session start.
        // At this point RF polling is enabled.
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        // If necessary, you may handle the error. Note session is no longer valid.
        // You must create a new session to restart RF polling.
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else {
            return
        }
        
        guard tags.count == 1 else {
            session.alertMessage = "More than 1 tags found. Please present only 1 tag."
            // TODO:
            return
        }
        
        // 通用處理
        switch tagMode {
        case .general:
            print(tag)
            var ndefTag: NFCNDEFTag
            switch tag {
            case let .iso7816(iso7816Tag):
                ndefTag = iso7816Tag
            case let .iso15693(iso15693Tag):
                ndefTag = iso15693Tag
            case let .miFare(miTag):
                ndefTag = miTag
            case let .feliCa(feTag):
                ndefTag = feTag
            @unknown default:
                session.invalidate(errorMessage: "Tag not valid.")
                return
            }
            session.connect(to: tag) { (error) in
                guard error == nil else {
                    session.restartPolling()
                    return
                }
                ndefTag.queryNDEFStatus { (status: NFCNDEFStatus, _, error: Error?) in
                    guard error == nil else {
                        session.invalidate(errorMessage: "query ndef error.")
                        return
                    }
                    guard status != .notSupported else {
                        session.invalidate(errorMessage: "Tag not support.")
                        return
                    }
                    ndefTag.readNDEF { (message: NFCNDEFMessage?, error: Error?) in
                        guard error == nil else {
                            session.invalidate(errorMessage: "Read error. Please try again.")
                            return
                        }
                        session.alertMessage = "Tag read success."
                        session.invalidate()
                        DispatchQueue.main.async {
                            guard let payload = message?.records.first else {
                                return
                            }
                            print(payload)
                            
                            self.infoLabel?.text = "TTT"
                        }
                    }
                }
            }
        case .polling:
            // by tag 做處理
            switch tag {
            case let .iso7816(iso7816Tag):
                self.detectedTag(session: session, tag: tag, ndefTag: iso7816Tag)
            case let .iso15693(iso15693Tag):
                self.detectedTag(session: session, tag: tag, ndefTag: iso15693Tag)
            case let .miFare(miTag):
                self.detectedTag(session: session, tag: tag, ndefTag: miTag)
            case let .feliCa(feTag):
                self.detectedTag(session: session, tag: tag, ndefTag: feTag)
            @unknown default:
                session.invalidate(errorMessage: "Tag not valid.")
                return
            }
        }
    }
    
    private func detectedTag(session: NFCTagReaderSession, tag: NFCTag, ndefTag: NFCISO7816Tag) {
        print("iso7816, aid = \(ndefTag.initialSelectedAID)")
        
        let tagUIDData = ndefTag.identifier
        var byteData: [UInt8] = []
        tagUIDData.withUnsafeBytes { byteData.append(contentsOf: $0) }
        var uidString = ""
        for byte in byteData {
            let decimalNumber = String(byte, radix: 16)
            if (Int(decimalNumber) ?? 0) < 10 {
                uidString.append("0\(decimalNumber)")
            } else {
                uidString.append(decimalNumber)
            }
        }
        debugPrint("\(byteData) converted to Tag UID: \(uidString)")
        session.connect(to: tag) { (error) in
            guard error == nil else {
                session.restartPolling()
                return
            }
            let myAPDU = NFCISO7816APDU(instructionClass: 0, instructionCode: 0xB0, p1Parameter: 0, p2Parameter: 0, data: Data(), expectedResponseLength: 16)
            if #available(iOS 14.0, *) {
                ndefTag.sendCommand(apdu: myAPDU) { result in
                    switch result {
                    case let .success(adpu):
                        debugPrint(adpu.statusWord1)
                        debugPrint(adpu.statusWord2)
                        session.alertMessage = "Tag read success."
                        session.invalidate()
                    case let .failure(error):
                        debugPrint("upper 14 >>> error = \(error.localizedDescription)")
                        session.invalidate(errorMessage: "Application failure")
                    }
                }
            } else {
                ndefTag.sendCommand(apdu: myAPDU) { (response: Data, sw1: UInt8, sw2: UInt8, error: Error?) in
                    // TODO: 依據資料格式做解析
                    if let error = error {
                        debugPrint("lower 14 >>> error = \(error.localizedDescription)")
                        session.invalidate(errorMessage: "Application failure")
                        return
                    }
                    print(String(data: response, encoding: .utf8) ?? "data is empty!!!")
                    session.alertMessage = "Tag read success."
                    session.invalidate()
                }
            }
        }
    }
    
    private func detectedTag(session: NFCTagReaderSession, tag: NFCTag, ndefTag: NFCISO15693Tag) {
        print("iso15693")
        session.connect(to: tag) { (error) in
            guard error == nil else {
                session.restartPolling()
                return
            }
            ndefTag.readSingleBlock(requestFlags: [.highDataRate, .address], blockNumber:0) { (response: Data, error: Error?) in
                // TODO: 依據資料格式做解析
                guard error != nil else {
                    session.invalidate(errorMessage: "Application failure")
                    return
                }
                session.alertMessage = "Tag read success."
                session.invalidate()
            }
        }
    }
    
    private func detectedTag(session: NFCTagReaderSession, tag: NFCTag, ndefTag: NFCMiFareTag) {
        print("mifare")
        session.connect(to: tag) { (error) in
            guard error == nil else {
                session.restartPolling()
                return
            }
            let myAPDU = NFCISO7816APDU(instructionClass: 0, instructionCode: 0xB0, p1Parameter: 0, p2Parameter: 0, data: Data(), expectedResponseLength: 16)
            ndefTag.sendMiFareISO7816Command(myAPDU) { (response: Data, sw1: UInt8, sw2: UInt8, error: Error?) in
                // TODO: 依據資料格式做解析
                guard error != nil else {
                    session.invalidate(errorMessage: "Application failure")
                    return
                }
                print(String(data: response, encoding: .utf8) ?? "data is empty!!!")
                session.alertMessage = "Tag read success."
                session.invalidate()
            }
        }
    }
    
    private func detectedTag(session: NFCTagReaderSession, tag: NFCTag, ndefTag: NFCFeliCaTag) {
        print("felica")
        session.connect(to: tag) { (error) in
            guard error == nil else {
                session.restartPolling()
                return
            }
            ndefTag.requestResponse() { (mode: Int, error: Error?) in
                // TODO: 依據資料格式做解析
                guard error != nil else {
                    session.invalidate(errorMessage: "Application failure")
                    return
                }
                session.alertMessage = "Tag read success."
                session.invalidate()
            }
        }
    }
}
