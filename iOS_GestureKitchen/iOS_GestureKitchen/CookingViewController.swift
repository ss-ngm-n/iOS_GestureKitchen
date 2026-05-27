//
//  CookingViewController.swift
//  iOS_GestureKitchen
//
//  Created by 김성민 on 5/27/26.
//

import UIKit
import AVFoundation
import Vision

class CookingViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    @IBOutlet weak var stepLabel: UILabel!
    @IBOutlet weak var timerLabel: UILabel!
    @IBOutlet weak var descriptionLabel: UILabel!
    
    @IBOutlet weak var prevArrowView: UIImageView!
    @IBOutlet weak var nextArrowView: UIImageView!
    @IBOutlet weak var cameraView: UIView!
    
    let steps = ["STEP 1/5", "STEP 2/5", "STEP 3/5", "STEP 4/5", "STEP 5/5"]
    let descriptions = ["파스타 면을 끓는 물에 8분간 삶아주세요. (소금 1큰술 추가)", "마늘은 편으로 썰고, 방울토마토는 반으로 잘라 준비합니다.", "팬에 올리브오일을 두르고 마늘을 볶아 향을 냅니다.", "방울토마토를 넣고 볶다가 살짝 으깨어 즙을 냅니다.", "삶은 면과 바질을 넣고 소스가 배어들게 볶아 완성합니다."]
    var currentIndex = 0
    
    var timer: Timer?
    var elapsedSeconds = 0
    
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    private var handPoseRequest = VNDetectHumanHandPoseRequest()
    
    private var wristPositionHistory: [CGPoint] = []
    private var lastActionTime = Date()
    private var stationaryStartTime: Date?
    private var stationaryStartLocation: CGPoint?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        updateUI()
        updateStopwatchText()
        handPoseRequest.maximumHandCount = 1
        checkCameraPermission()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = cameraView.bounds
    }
    
    @objc func goToPrevStep(){
        if currentIndex > 0{
            currentIndex -= 1
            updateUI()
        }
    }
    
    @objc func goToNextStep(){
        if currentIndex < steps.count - 1{
            currentIndex += 1
            updateUI()
        }
    }
    
    @objc func toggleStopwatch(){
        if timer != nil{
            timer?.invalidate()
            timer = nil
        }else{
            timer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(updateStopwatch), userInfo: nil, repeats: true)
        }
    }
    
    @objc func resetStopwatch(){
        timer?.invalidate()
        timer = nil
        elapsedSeconds = 0
        updateStopwatchText()
    }
    
    @IBAction func prevArrowTapped(_ sender: UITapGestureRecognizer) {
        goToPrevStep()
    }
    
    @IBAction func nextArrowTapped(_ sender: UITapGestureRecognizer) {
        goToNextStep()
    }
    
    @IBAction func playPauseTapped(_ sender: UITapGestureRecognizer) {
        toggleStopwatch()
    }
    
    @IBAction func resetTapped(_ sender: UITapGestureRecognizer) {
        resetStopwatch()
    }
    
    func updateUI(){
        stepLabel.text = steps[currentIndex]
        descriptionLabel.text = descriptions[currentIndex]
        
        if currentIndex == 0{
            prevArrowView.alpha = 0.3
            prevArrowView.isUserInteractionEnabled = false
        }else{
            prevArrowView.alpha = 1.0
            prevArrowView.isUserInteractionEnabled = true
        }
        
        if currentIndex == steps.count - 1{
            nextArrowView.alpha = 0.3
            nextArrowView.isUserInteractionEnabled = false
        }else{
            nextArrowView.alpha = 1.0
            nextArrowView.isUserInteractionEnabled = true
        }
    }
    
    @objc func updateStopwatch(){
        elapsedSeconds += 1
        updateStopwatchText()
    }
    
    func updateStopwatchText(){
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        timerLabel.text = String(format: "%02d:%02d", minutes, seconds)
    }
    
    func checkCameraPermission(){
        switch AVCaptureDevice.authorizationStatus(for: .video){
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) {granted in if granted{
                DispatchQueue.main.async{self.setupCamera()}
            }else {
                print("사용자가 카메라 권한을 거부했습니다.")
            }}
        default: print("카메라 권한이 거부되었습니다.")
        }
    }
    
    func setupCamera(){
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high
        
        guard let videoCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else{return}
        guard let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice)else{return}
        
        if captureSession.canAddInput(videoInput){
            captureSession.addInput(videoInput)
        }else{return}
        
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        
        if captureSession.canAddOutput(videoDataOutput){
            captureSession.addOutput(videoDataOutput)
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = cameraView.bounds
        previewLayer.videoGravity = .resizeAspectFill
        cameraView.layer.addSublayer(previewLayer)
        
        DispatchQueue.global(qos: .background).async {self.captureSession.startRunning()}
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection){
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .leftMirrored, options: [:])
        
        do{
            try handler.perform([handPoseRequest])
            
            guard let observation = handPoseRequest.results?.first else{
                wristPositionHistory.removeAll()
                stationaryStartTime = nil
                return
            }
            
            let wristPoints = try observation.recognizedPoints(.all)
            guard let wrist = wristPoints[.wrist], wrist.confidence > 0.3 else {return}
            let currentWristLocation = wrist.location
            
            var isOpenPalm = false
            var isClosedFist = false
            
            if let middleTip = wristPoints[.middleTip], middleTip.confidence > 0.3{
                let distance = hypot(middleTip.location.x - wrist.location.x, middleTip.location.y - wrist.location.y)
                isOpenPalm = distance > 0.2
                isClosedFist = distance < 0.2
            }
            
            guard Date().timeIntervalSince(lastActionTime) > 1.5 else {return}
            
            if let startLoc = stationaryStartLocation, let startTime = stationaryStartTime{
                let moveDistance = hypot(currentWristLocation.x - startLoc.x, currentWristLocation.y - startLoc.y)
                
                if moveDistance < 0.15{
                    if Date().timeIntervalSince(startTime) > 2.0{
                        if isOpenPalm{
                            print("2초 손 펴짐 인식! 스톱워치 토글")
                            DispatchQueue.main.async{self.toggleStopwatch()}
                            lastActionTime = Date()
                        }else if isClosedFist{
                            print("2초 주먹 쥠 인식! 스톱워치 리셋")
                            DispatchQueue.main.async{self.resetStopwatch()}
                            lastActionTime = Date()
                        }
                        stationaryStartTime = nil
                        
                    }
                }else{
                    stationaryStartLocation = currentWristLocation
                    stationaryStartTime = Date()
                }
            }else{
                stationaryStartLocation = currentWristLocation
                stationaryStartTime = Date()
            }
            wristPositionHistory.append(currentWristLocation)
                
            if wristPositionHistory.count > 15{wristPositionHistory.removeFirst()}
                
            if wristPositionHistory.count == 15{
                let firstPosition = wristPositionHistory.first!
                let lastPosition = wristPositionHistory.last!
                    
                let deltaX = lastPosition.x - firstPosition.x
                let deltaY = lastPosition.y - firstPosition.y
                    
                if abs(deltaX) > 0.25 && abs(deltaX) > abs(deltaY) * 1.5{
                    if deltaX > 0{
                        print("스와이프! 이전 페이지")
                        DispatchQueue.main.async{self.goToPrevStep()}
                    }else{
                        print("스와이프! 다음 페이지")
                        DispatchQueue.main.async{self.goToNextStep()}
                    }
                        
                    wristPositionHistory.removeAll()
                    lastActionTime = Date()
                }
            }
        } catch {
            print("Vision 분석 에러: \(error)")
        }
    }
    
}
