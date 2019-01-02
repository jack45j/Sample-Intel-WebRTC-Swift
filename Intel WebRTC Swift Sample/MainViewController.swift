//
//  MainViewController.swift
//  testIntelWebRTC
//
//  Created by 林翌埕 on 2018/12/13.
//  Copyright © 2018 Benson Lin. All rights reserved.
//

import UIKit
import AFNetworking

class MainViewController: UIViewController {
    
    /// Set to your conference Server
    /// ex: https://example.com:3004
    ///
    let basicServerString = ""
    
    @IBOutlet weak var remoteVideoView: RTCEAGLVideoView!
    
    var capture: RTCCameraVideoCapturer?
    var mixedStream: ICSRemoteMixedStream?
    var localStream: ICSLocalStream?
    var remoteStream: ICSRemoteStream?
    var conferenceSubsciption: ICSConferenceSubscription?
    var conferenceClient: ICSConferenceClient?
    var publication: ICSConferencePublication?
    var conferenceID: String?
    
    var isSpeakerMode: Bool = true
    
    /// Switch between speaker mode and normal style.
    ///
    @IBAction func pressedSpeakerModeButton(_ sender: Any) {
        if isSpeakerMode {
            do {
                try AVAudioSession.sharedInstance().overrideOutputAudioPort(AVAudioSession.PortOverride.none)
                isSpeakerMode = !isSpeakerMode
            } catch {
                
            }
        } else {
            do {
                try AVAudioSession.sharedInstance().overrideOutputAudioPort(AVAudioSession.PortOverride.speaker)
                isSpeakerMode = !isSpeakerMode
            } catch {
                
            }
        }
    }
    
    /// Hang up button pressed.
    ///
    @IBAction func pressedHangUpButton(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
        conferenceClient?.leaveWith(onSuccess: {
            self.quitConference()
        }, onFailure: { (error) in
            self.quitConference()
            print(error.localizedDescription)
        })
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureConferenctClient()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        getTokenFromBasicSample(basicServerString, onSuccess: { (token) in
            print("token: \(token!)")
            self.joinRoom(by: token)
        }, onFailure: {
            print("getToken error.")
        })
    }
}


extension MainViewController {
    
    func configureConferenctClient() {
        conferenceClient = ICSConferenceClient(configuration: conferenceClientConfiguration())
        conferenceClient?.delegate = self
    }
    
    func conferenceClientConfiguration() -> ICSConferenceClientConfiguration {
        let config = ICSConferenceClientConfiguration()
        let ice = [RTCIceServer(urlStrings: ["stun:61.152.239.47:3478"])]
        config.rtcConfiguration = RTCConfiguration()
        config.rtcConfiguration.iceServers = ice
        
        return config
    }
    
    /// Always get token before join room
    /// join sample room if room value is empty.
    ///
    func getTokenFromBasicSample(_ serverString: String?, onSuccess: @escaping (String?) -> Void, onFailure: @escaping () -> Void) {
        let manager = AFHTTPRequestOperationManager()
        manager.requestSerializer = AFJSONRequestSerializer()
        manager.requestSerializer.setValue("*/*", forHTTPHeaderField: "Accpet")
        manager.requestSerializer.setValue("application/json", forHTTPHeaderField: "Content-Type")
        manager.responseSerializer = AFHTTPResponseSerializer()
        manager.securityPolicy.allowInvalidCertificates = false
        manager.securityPolicy.validatesDomainName = true
        let params = ["room":"",
                      "username":"user",
                      "role":"presenter"]
        
        manager.post(serverString! + "createToken/", parameters: params, success: { (operation, response) in
            let data = Data(base64Encoded: response as! Data)
            onSuccess(String(data: data!, encoding: .utf8))
        }, failure: { (operation, error) in
            print("Error: \(error.localizedDescription)")
        })
    }
    
    /// join room with token.
    /// Call getTokenFromBasicSample first before join room.
    ///
    func joinRoom(by token: String?) {
        conferenceClient?.join(withToken: token!, onSuccess: { (conferenceInfo) in
            if conferenceInfo.remoteStreams.count > 0 {
                
                for stream in conferenceInfo.remoteStreams {
                    stream.delegate = self
                    self.conferenceID = conferenceInfo.conferenceId
                    if stream is ICSRemoteMixedStream {
                        self.mixedStream = stream as? ICSRemoteMixedStream
                    }
                }
            }
            self.doPublish()
        }, onFailure: { (error) in
            print(error.localizedDescription)
        })
    }
    
    /// Publish local stream to conference.
    /// constraints seems need to be the same as conference server's settings or it will crash with error.
    ///
    func doPublish(isAudioOnly: Bool = false, CameraDirection: AVCaptureDevice.Position = .front) {
        let constraints = ICSStreamConstraints()
        constraints.audio = true
        if isAudioOnly == false {
            constraints.video = ICSVideoTrackConstraints()
            constraints.video?.frameRate = 30
            constraints.video?.resolution = CGSize(width: 640, height: 480)
            constraints.video?.devicePosition = CameraDirection
        }
        
        var err: NSError?
        localStream = ICSLocalStream(constratins: constraints, error: &err)
        localVideoView.captureSession = capture?.captureSession
        
        let options = ICSPublishOptions()
        let opusParams = ICSAudioCodecParameters()
        opusParams.name = ICSAudioCodec.opus
        let audioParams = ICSAudioEncodingParameters()
        options.audio = [audioParams]
        let h264Params = ICSVideoCodecParameters()
        h264Params.name = ICSVideoCodec.H264
        let videoParams = ICSVideoEncodingParameters()
        videoParams.codec = h264Params
        options.video = [videoParams]
        
        conferenceClient?.publish(localStream!, with: nil, onSuccess: { (pub) in
            self.publication = pub
            self.publication?.delegate = self
            self.mix(toCommonView: pub)
        }, onFailure: { (error) in
            print(error.localizedDescription)
        })
        
        remoteStream = mixedStream
        subscribeStream()
    }
    
    /// subscribe remote mixed stream from conference.
    ///
    func subscribeStream() {
        let subscribeOption = ICSConferenceSubscribeOptions()
        subscribeOption.video = ICSConferenceVideoSubscriptionConstraints()
        
        var width:CGFloat = 0.0
        var height:CGFloat = 0.0
        for value in (mixedStream?.capabilities.video.resolutions)! {
            let resolution = value.cgSizeValue
            if resolution.width == 640 && resolution.height == 480 {
                width = resolution.width
                height = resolution.height
                break
            }
            if resolution.width < width && resolution.height != 0 {
                width = resolution.width
                height = resolution.height
            }
        }
        
        conferenceClient?.subscribe(mixedStream!, with: subscribeOption, onSuccess: { (subscription) in
            self.conferenceSubsciption = subscription
            self.conferenceSubsciption!.delegate = self
            
            self.remoteStream = self.mixedStream
            self.remoteStream?.attach(self.remoteVideoView!)
            
        }, onFailure: { (error) in
            print(error.localizedDescription)
        })
    }
    
    func mix(toCommonView publication: ICSConferencePublication) {
        let manager = AFHTTPRequestOperationManager()
        manager.requestSerializer = AFJSONRequestSerializer()
        manager.requestSerializer.setValue("*/*", forHTTPHeaderField: "Accpet")
        manager.requestSerializer.setValue("application/json", forHTTPHeaderField: "Content-Type")
        manager.responseSerializer = AFHTTPResponseSerializer()
        manager.securityPolicy.allowInvalidCertificates = false
        manager.securityPolicy.validatesDomainName = true
        let params = ["op":"replace",
                      "path":"/info/inViews",
                      "value":"common"]
        let paramsList = [params]
        
        print("RoomID: \(conferenceID!) and Streams: \(publication.publicationId)")
        manager.patch("\(basicServerString)rooms/\(conferenceID!)/streams/\(publication.publicationId)", parameters: paramsList, success: nil, failure: {(operation, error) in
            print(error)
        })
    }
    
    func quitConference() {
        localStream = nil
        if capture != nil {
            capture?.stopCapture()
        }
        conferenceClient = nil
    }
}


extension MainViewController: ICSConferenceClientDelegate {
    func conferenceClientDidDisconnect(_ client: ICSConferenceClient) {
        print(#function)
    }
    
    func conferenceClient(_ client: ICSConferenceClient, didAdd stream: ICSRemoteStream) {
        print(#function)
    }
    
    func conferenceClient(_ client: ICSConferenceClient, didAdd user: ICSConferenceParticipant) {
        print(#function)
    }
    
    func conferenceClient(_ client: ICSConferenceClient, didReceiveMessage message: String, from senderId: String, to targetType: String) {
        print(#function)
    }
}


/// MARK: ICSRemoteStreamDelegate
///
extension MainViewController: ICSRemoteStreamDelegate {
    func streamDidEnd(_ stream: ICSRemoteStream) {
        print("stream: \(stream.origin) ended.")
    }
    
    func streamDidUpdate(_ stream: ICSRemoteStream) {
        print("stream: \(stream.origin) updated.")
    }
}


/// MARK: ICSConferencePublicationDelegate
///
extension MainViewController: ICSConferencePublicationDelegate {
    func publicationDidEnd(_ publication: ICSConferencePublication) {
        print(#function)
    }
    
    func publicationDidMute(_ publication: ICSConferencePublication, trackKind kind: ICSTrackKind) {
        print(#function)
    }
    
    func publicationDidUnmute(_ publication: ICSConferencePublication, trackKind kind: ICSTrackKind) {
        print(#function)
    }
}


/// MARK: ICSConferenceSubscriptionDelegate
///
extension MainViewController: ICSConferenceSubscriptionDelegate {
    func subscriptionDidEnd(_ subscription: ICSConferenceSubscription) {
        print(#function)
    }
    
    func subscriptionDidMute(_ subscription: ICSConferenceSubscription, trackKind kind: ICSTrackKind) {
        print(#function)
    }
    
    func subscriptionDidUnmute(_ subscription: ICSConferenceSubscription, trackKind kind: ICSTrackKind) {
        print(#function)
    }
}
