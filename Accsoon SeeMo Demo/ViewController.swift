//
//  ViewController.swift
//  Accsoon SeeMo Demo
//
//  Created by Nguyen Hoang on 13/3/26.
//

import AVFoundation
import UIKit

class ViewController: UIViewController {
    var seemoCapture: SeemoCapture?
    private var displayLayer = AVSampleBufferDisplayLayer()

    override func viewDidLoad() {
        super.viewDidLoad()

        setupDisplayLayer()

        seemoCapture = SeemoCapture()

        seemoCapture?.onUSBPlug = { manufacturer, deviceName in
            print("Device: \(manufacturer ?? "unknow") - \(deviceName ?? "unknow")")
        }

        seemoCapture?.onUSBUnplug = {
            print("Device: onUSBUnplug")
        }

        seemoCapture?.onVideoSampleBuffer = { [weak self] buffer in
            guard let self = self else { return }

            DispatchQueue.main.async {
                let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
                print("ViewController: received video sampleBuffer, pts=\(pts.seconds), ready=\(self.displayLayer.isReadyForMoreMediaData)")
                
                if self.displayLayer.isReadyForMoreMediaData {
                    self.displayLayer.enqueue(buffer)
                    print("ViewController: enqueued sampleBuffer to displayLayer")
                } else {
                    print("ViewController: displayLayer not ready, dropping frame")
                }
            }
        }
    }

    private func setupDisplayLayer() {
        debugPrint("Did load setup display player for hardware")
        displayLayer.frame = view.bounds
        displayLayer.videoGravity = .resizeAspect
        view.layer.addSublayer(displayLayer)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        debugPrint("didlayout sub view")
        
        displayLayer.frame = view.bounds
    }
}
