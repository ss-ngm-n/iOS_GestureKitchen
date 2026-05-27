import UIKit
import AVFoundation
import Vision

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    @IBOutlet weak var cameraView: UIView!
    
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    private var handPoseRequest = VNDetectHumanHandPoseRequest()
    
    // MARK: - 제스처 인식을 위한 상태 변수들
    private var wristPositionHistory: [CGPoint] = [] // 스와이프를 위한 손목 위치 기록
    private var lastActionTime = Date()              // 중복 인식 방지용 (쿨다운)
    private var stationaryStartTime: Date?           // 정지 상태가 시작된 시간
    private var stationaryStartLocation: CGPoint?    // 정지 상태가 시작된 위치
    
    override func viewDidLoad() {
        super.viewDidLoad()
        handPoseRequest.maximumHandCount = 1
        checkCameraPermission()
    }
    
    func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video){
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in if granted {
                DispatchQueue.main.async { self.setupCamera() }
                } else {
                print("사용자가 카메라 권한을 거부했습니다.")
                }
            }
        default: print("카메라 권한이 거부되었습니다. 설정에서 권한을 허용해주세요.")
        }
    }
    
    func setupCamera(){
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high
        
        guard let videoCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else { return }
        guard let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice) else { return }
        
        if captureSession.canAddInput(videoInput){
            captureSession.addInput(videoInput)
        } else {
            print("카메라 입력을 추가할 수 없습니다.")
            return
        }
        
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
        
        DispatchQueue.global(qos: .background).async { self.captureSession.startRunning() }
    }
    
    override func viewDidLayoutSubviews(){
        super.viewDidLayoutSubviews()
        previewLayer?.frame = cameraView.bounds
    }
    
    // MARK: - Vision 프레임워크 분석
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection){
        
        // ⭐️ 전면 카메라 거울 모드 적용 (.leftMirrored)
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .leftMirrored, options: [:])
        
        do{
            try handler.perform([handPoseRequest])
            
            // 화면에 손이 없으면 누적된 데이터 초기화
            guard let observation = handPoseRequest.results?.first else {
                wristPositionHistory.removeAll()
                stationaryStartTime = nil
                return
            }
            
            // 손목(wrist)과 중지 끝(middleTip) 좌표 추출
            let wristPoints = try observation.recognizedPoints(.all)
            guard let wrist = wristPoints[.wrist], wrist.confidence > 0.3 else { return }
            let currentWristLocation = wrist.location
            
            // 손바닥이 펴져 있는지 확인하는 변수 (손목과 중지 끝의 거리가 일정 이상 떨어져 있으면 쫙 편 것으로 간주)
            var isOpenPalm = false
            if let middleTip = wristPoints[.middleTip], middleTip.confidence > 0.3 {
                let distance = hypot(middleTip.location.x - wrist.location.x, middleTip.location.y - wrist.location.y)
                isOpenPalm = distance > 0.2 // 필요에 따라 이 수치(0.2)를 조절하세요.
            }
            
            // ⭐️ 제스처 쿨다운 체크 (액션이 터지고 1.5초 안에는 다른 액션 무시)
            guard Date().timeIntervalSince(lastActionTime) > 1.5 else { return }
            
            // -----------------------------------------------------
            // 1️⃣ [제스처 1] 손바닥 편 상태로 2초 유지 (타이머 시작/정지)
            // -----------------------------------------------------
            if isOpenPalm {
                if let startLoc = stationaryStartLocation, let startTime = stationaryStartTime {
                    // 시작 위치에서 얼마나 움직였는지 확인
                    let moveDistance = hypot(currentWristLocation.x - startLoc.x, currentWristLocation.y - startLoc.y)
                    
                    if moveDistance < 0.1 { // 거의 안 움직였을 때 (0.05 반경 이내)
                        if Date().timeIntervalSince(startTime) >= 1.5 {
                            print("⏱️ 2초 정지 인식 완료! 타이머 시작/일시정지 토글!")
                            
                            // ⭐️ UI 변경이나 타이머 로직은 반드시 메인 스레드에서 실행
                            DispatchQueue.main.async {
                                // TODO: 여기에 타이머 시작/정지 코드를 넣으세요.
                            }
                            
                            lastActionTime = Date()
                            stationaryStartTime = nil // 초기화
                            return // 스와이프 로직은 건너뜀
                        }
                    } else {
                        // 손이 너무 많이 움직였으면 타이머 리셋
                        stationaryStartLocation = currentWristLocation
                        stationaryStartTime = Date()
                    }
                } else {
                    // 정지 체크 최초 시작
                    stationaryStartLocation = currentWristLocation
                    stationaryStartTime = Date()
                }
            } else {
                // 손바닥을 오므리면 정지 타이머 리셋
                stationaryStartTime = nil
            }
            
            // -----------------------------------------------------
            // 2️⃣ [제스처 2] 좌우 스와이프 (페이지 넘기기)
            // -----------------------------------------------------
            wristPositionHistory.append(currentWristLocation)
            
            // 최근 15프레임(약 0.5초)의 기록만 유지
            if wristPositionHistory.count > 15 {
                wristPositionHistory.removeFirst()
            }
            
            if wristPositionHistory.count == 15 {
                let firstPosition = wristPositionHistory.first!
                let lastPosition = wristPositionHistory.last!
                
                let deltaX = lastPosition.x - firstPosition.x
                let deltaY = lastPosition.y - firstPosition.y
                
                // 가로 이동 거리가 세로 이동 거리보다 훨씬 크고, 0.25(화면의 25%) 이상 크게 움직였을 때
                if abs(deltaX) > 0.25 && abs(deltaX) > abs(deltaY) * 1.5 {
                    if deltaX > 0 {
                        print("👉 오른쪽으로 스와이프! (이전 페이지)")
                        DispatchQueue.main.async {
                            // TODO: 이전 페이지 넘기기 코드
                        }
                    } else {
                        print("👈 왼쪽으로 스와이프! (다음 페이지)")
                        DispatchQueue.main.async {
                            // TODO: 다음 페이지 넘기기 코드
                        }
                    }
                    
                    // 인식 성공 후 초기화 및 쿨다운 적용
                    wristPositionHistory.removeAll()
                    lastActionTime = Date()
                }
            }
            
        } catch {
            print("Vision 분석 에러: \(error)")
        }
    }
}
