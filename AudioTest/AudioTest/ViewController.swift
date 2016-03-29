//
//  ViewController.swift
//  AudioTest
//
//  Created by yxk on 16/3/21.
//  Copyright © 2016年 yxk. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    var decoder: KxMovieDecoder!
    var artworkFrame: KxArtworkFrame!
    var dispatchQueue: dispatch_queue_t!
    var audioFrames: NSMutableArray!
    var subtitles: NSMutableArray!
    
    var minBufferedDuration: Float = 0
    var maxBufferedDuration: Float = 0
    var bufferedDuration: Float = 0
    var parameters: NSMutableDictionary!
    var gHistory: NSMutableDictionary = NSMutableDictionary()
    
    var interrupted: Bool = false
    var playing: Bool = false
    var decoding: Bool = false
    var buffered: Bool = false
    
    var currentAudioFrame: NSData!
    var moviePosition: CGFloat = 0
    var currentAudioFramePos: Int = 0
    
    
    var tickCorrectionTime: NSTimeInterval!
    var tickCorrectionPosition: NSTimeInterval!
    var debugStartTime: NSTimeInterval = 0
    var tickCounter: Int = 0
    
    var debugAudioStatus: Int = 0
    var debugAudioStatusTS: NSDate!
    
    
    @IBOutlet weak var titleLable: UILabel!
    
    @IBOutlet weak var imageView: UIImageView!
    
    @IBOutlet weak var progressSlider: UISlider!
    
    @IBOutlet weak var leftProgress: UILabel!
    
    @IBOutlet weak var rightProgress: UILabel!
    
    var songsArray: [String] = []
    var currentIndex: Int = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
       
        var path: String = NSBundle.mainBundle().pathForResource("越难越爱", ofType: "mp3")!
        songsArray.append(path)
        path = NSBundle.mainBundle().pathForResource("ss", ofType: "flac")!
        songsArray.append(path)
        progressSlider.autoresizingMask = .FlexibleWidth
        progressSlider.continuous = false
        progressSlider.value = 0
        progressSlider.addTarget(self, action: "progressDidChange:", forControlEvents: .ValueChanged)
        
        //-----
        var audioManager = KxAudioManager.audioManager()
        audioManager.activateAudioSession()
        
        initSongs(songsArray[0])
    }
    

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func initSongs(path: String) {
        //set parameters
        moviePosition = 0
        parameters = NSMutableDictionary()
        parameters["KxMovieParameterDisableDeinterlacing"] = true
        let decoder = KxMovieDecoder()
        decoder.interruptCallback = {[weak self]() -> Bool in
            if let weakSelf = self {
                return weakSelf.interrupted
            }
            return false
        }
        
        dispatch_async(dispatch_get_global_queue(0, 0)) { [weak self]() -> Void in
            
            try? decoder.openFile(path)
            
            dispatch_sync(dispatch_get_main_queue()) { [weak self]() -> Void in
                if let weakSelf = self {
                    weakSelf.setingDecoder(decoder)
                    
                }
            }
            
            
        }
    }
   
    
    func setingDecoder(decoder: KxMovieDecoder) {
        
        
        self.decoder = decoder
        self.moviePosition = decoder.position
        self.dispatchQueue = dispatch_queue_create("KxMovie", DISPATCH_QUEUE_SERIAL)
        self.audioFrames = NSMutableArray()
        if decoder.subtitleStreamsCount > 0 {
            subtitles = NSMutableArray()
        }
        minBufferedDuration = 0.2
        maxBufferedDuration = 0.4
        if decoder.validAudio {
            minBufferedDuration *= 10.0
        }
        if parameters.count > 0 {
            var val = parameters.valueForKey("KxMovieParameterMinBufferedDuration")
            if val != nil && val!.isKindOfClass(NSNumber) {
                minBufferedDuration = val!.floatValue
            }
            val = parameters.valueForKey("KxMovieParameterMaxBufferedDuration")
            if val != nil && val!.isKindOfClass(NSNumber) {
                maxBufferedDuration = val!.floatValue
            }
            val = parameters.valueForKey("KxMovieParameterDisableDeinterlacing")
            if val != nil && val!.isKindOfClass(NSNumber) {
                self.decoder.disableDeinterlacing = val!.boolValue
            }
            if maxBufferedDuration < minBufferedDuration {
                maxBufferedDuration = minBufferedDuration * 2
            }
        
        }
        print("buffered limit: %.1f - %.1f,\(minBufferedDuration)----\(minBufferedDuration)")
        self.restorePlay()
        //设置信息
        var title =  self.decoder.info["metadata"]!["title"] as? String
        if title == nil {
            title =  self.decoder.info["metadata"]!["TITLE"] as? String
        }
        self.titleLable.text = title
        if self.decoder.validAudio {
            if self.artworkFrame != nil {
                self.imageView.image = self.artworkFrame.asImage()
                self.artworkFrame = nil
            }
        }
        
        
    }
    func updateTimer() {
        let duration = self.decoder.duration
        let position = moviePosition - self.decoder.startTime
        if progressSlider.state == .Normal {
            progressSlider.value = Float(position) / Float(duration)
            leftProgress.text = formatTimeInterval(position, isLeft: false)
        }
        if Float(self.decoder.duration) != MAXFLOAT {
            rightProgress.text = formatTimeInterval(self.decoder.duration - position, isLeft: true)
        }
        

    }
    func formatTimeInterval(seconds: CGFloat, isLeft: Bool) -> String {
        let secondsTemp = max(0, seconds)
        var s: Int = Int(secondsTemp)
        var m: Int = s / 60
        var h: Int = m / 60
        s = s % 60
        m = m % 60
        var format: NSMutableString = (isLeft && secondsTemp >= 0.5 ? "-" : "").mutableCopy() as! NSMutableString
        if h != 0 {
            format.appendFormat("%d:%0.2d", h, m)
        }
        else {
            format.appendFormat("%d", m)
        }
        format.appendFormat(":%0.2d", s)
        return format as String
        
    }
    
    func restorePlay() {
        let n = gHistory.valueForKey(self.decoder!.path)
//        if (n != nil) {
//            
//        }else{
            self.play()
//        }
        
    }
    func play() {
        if playing || !self.decoder.validAudio || self.interrupted {
            return
        }
        self.playing = true
        self.interrupted = false
        self.tickCorrectionTime = 0
        self.tickCounter = 0
        self.debugStartTime = -1
        self.asyncDecodeFrames()
        let popTime = dispatch_time(DISPATCH_TIME_NOW, Int64(0.1 * Double(NSEC_PER_SEC)))
        dispatch_after(popTime, dispatch_get_main_queue()) { () -> Void in
            self.tick()
        }
        if self.decoder.validAudio {
            self.enableAudio(true)
        }
        print("play movie")
        
    }
    func asyncDecodeFrames() {
        if self.decoding {
            return
        }
        let weakSelf = self
        let weakDecoder = self.decoder
        let duration: CGFloat = 0.1
        self.decoding = true
        dispatch_async(self.dispatchQueue) { () -> Void in
            if !weakSelf.playing {
                return
            }
            var good = true
            while(good) {
                good = false
                autoreleasepool({ () -> () in
                    if weakDecoder != nil && weakDecoder.validAudio {
                        let frames: [KxMovieFrame] = weakDecoder.decodeFrames(duration) as! [KxMovieFrame]
                        if frames.count > 0 {
                            good = weakSelf.addFrames(frames)
                        }
                    
                    }
                })
            
            }
            weakSelf.decoding = false
            
        }
        
    
    }
    func addFrames(frames: [KxMovieFrame]) -> Bool {
        if self.decoder.validAudio {
            for var frame: KxMovieFrame in frames {
                if frame.type == KxMovieFrameTypeAudio {
                    audioFrames.addObject(frame)
                    if !decoder.validVideo {
                        bufferedDuration += Float(frame.duration)
                    }
                }
            }
            for var frame in frames {
                if frame.type == KxMovieFrameTypeArtwork {
                    self.artworkFrame = frame as! KxArtworkFrame
                }
            }
        
        }
        return self.playing && bufferedDuration < maxBufferedDuration
    }
    func enableAudio(on: Bool) {
        let audioManager = KxAudioManager.audioManager()
        if on && decoder.validAudio {
            audioManager.outputBlock = {(outData: UnsafeMutablePointer<Float>,numFrames: UInt32, numChannels: UInt32) -> Void in
                self.audioCallbackFillData(outData, numFrames: Int(numFrames), numChannels: Int(numChannels))
            }
            audioManager.play()
            print("audio device smr\(audioManager.samplingRate),-\(audioManager.numBytesPerSample),-\(audioManager.numOutputChannels)")
        }else{
            print("audio pause")
            audioManager.pause()
            audioManager.outputBlock = nil
        }
    }
    func audioCallbackFillData(outData: UnsafeMutablePointer<Float>, numFrames: Int, numChannels: Int) {
        var numFrames = numFrames
        var weakOutData = outData

        if buffered {
            memset(weakOutData, 0, numFrames * numChannels * sizeof(Float))
            
            return
        }
        while numFrames > 0 {
            if currentAudioFrame == nil {
                let count: Int = audioFrames.count
                if count > 0 {
                    var frame: KxAudioFrame = audioFrames[0] as! KxAudioFrame
                    audioFrames.removeObjectAtIndex(0)
                    moviePosition = frame.position
                    bufferedDuration -= Float(frame.duration)
                    currentAudioFramePos = 0
                    currentAudioFrame = frame.samples
                }
            }
            if (currentAudioFrame != nil) {
                let bytes = currentAudioFrame.bytes + currentAudioFramePos
                let bytesLeft: Int = (currentAudioFrame.length - currentAudioFramePos)
                let frameSizeOf: Int = numChannels * sizeof(Float)
                let bytesToCopy: Int = min(numFrames * frameSizeOf, bytesLeft)
                let framesToCopy: Int = bytesToCopy / frameSizeOf
                memcpy(weakOutData, bytes, bytesToCopy)
                numFrames -= framesToCopy
                weakOutData = weakOutData.advancedBy(framesToCopy * numChannels)
                
                if bytesToCopy < bytesLeft {
                    self.currentAudioFramePos += bytesToCopy
                }
                else {
                    self.currentAudioFrame = nil
                }
                
            }else{
                memset(weakOutData, 0, numFrames * numChannels * sizeof(Float))
                //LoggerStream(1, @"silence audio");
                self.debugAudioStatus = 3
                self.debugAudioStatusTS = NSDate()
                break
            }
        }
    
    }
    func tick() {
        // The output below is limited by 1 KB.
        // Please Sign Up (Free!) to remove this limitation.
        
        if buffered && ((bufferedDuration > minBufferedDuration) || decoder.isEOF) {
            self.tickCorrectionTime = 0
            self.buffered = false
        }
        var interval: NSTimeInterval = 0
        if !buffered {
            
            interval = self.presentFrame()
        }
        if self.playing {
            let leftFrames: Int = (decoder.validAudio ? audioFrames.count : 0)
            if 0 == leftFrames {
                if decoder.isEOF {
                    self.pause()
                    self.updateTimer()
                    return
                }
                if minBufferedDuration > 0 && !buffered {
                    self.buffered = true
//                    activityIndicatorView.startAnimating()
                }
            }
            if leftFrames <= 0 || !(bufferedDuration > minBufferedDuration) {
                self.asyncDecodeFrames()
            }
            let correction: NSTimeInterval = self.tickCorrection()
            let time: NSTimeInterval = max(interval + correction, 0.01)
            var popTime: dispatch_time_t = dispatch_time(DISPATCH_TIME_NOW, Int64(time) * Int64(NSEC_PER_SEC))
            dispatch_after(popTime, dispatch_get_main_queue(), { () -> Void in
                self.tick()
            })
        }
        if (tickCounter++) % 3 == 0 {
            self.updateTimer()
        }
    
    }
    func tickCorrection() -> NSTimeInterval {
        if buffered {
            return 0
        }
        let now: NSTimeInterval = NSDate.timeIntervalSinceReferenceDate()
        if (tickCorrectionTime == 0) {
            self.tickCorrectionTime = now
            self.tickCorrectionPosition = NSTimeInterval( moviePosition)
            return 0
        }
        let dPosition: NSTimeInterval = NSTimeInterval(moviePosition) - tickCorrectionPosition
        var dTime: NSTimeInterval = now - tickCorrectionTime
        var correction: NSTimeInterval = dPosition - dTime
        //if ((_tickCounter % 200) == 0)
        //    LoggerStream(1, @"tick correction %.4f", correction);
        if correction > 1.0 || correction < -1.0 {
            print("tick correction reset\(correction)")
            correction = 0
            self.tickCorrectionTime = 0
        }
        return correction
    
    
    }
    func presentFrame() -> NSTimeInterval {
        var interval: NSTimeInterval = 0
        
        
       
        if self.playing && debugStartTime < 0 {
            self.debugStartTime = NSDate.timeIntervalSinceReferenceDate() - NSTimeInterval(moviePosition)
        }
        return interval
    }


    @IBAction func playClick(sender: AnyObject) {
        if self.playing {
            self.pause()
        }else{
            self.play()
        }
    }
    func progressDidChange(sender: UISlider) {
        self.setingMoviePosition(sender.value * Float(self.decoder.duration))
        
    }
    func setingMoviePosition(position: Float) {
        let playMode = self.playing
        self.playing = false
        self.enableAudio( false)
        
        let popTime = dispatch_time(DISPATCH_TIME_NOW, Int64(0.1 * Double(NSEC_PER_SEC)))
        dispatch_after(popTime, dispatch_get_main_queue()) { () -> Void in
            self.updatePosition(position , playMode: playMode)
        }
    }
    func updatePosition(position: Float, playMode: Bool) {
        self.freeBufferedFrames()
        var positionTemp = position
        positionTemp = min(Float(decoder.duration - 1), max(0, positionTemp))
        dispatch_async(self.dispatchQueue) { [weak self]() -> Void in
            if let weakSelf = self {
                if playMode {
                    weakSelf.decoder.position = CGFloat(positionTemp)
                    dispatch_async(dispatch_get_main_queue(), { () -> Void in
                        weakSelf.moviePosition = weakSelf.decoder.position
                        weakSelf.play()
                    })
                    
                }else{
                    weakSelf.decoder.position = CGFloat(positionTemp)
                    weakSelf.decodeFrames()
                    dispatch_async(dispatch_get_main_queue(), { () -> Void in
                        weakSelf.moviePosition = weakSelf.decoder.position
                        weakSelf.presentFrame()
                        weakSelf.updateTimer()
                    })
                }
            }
        }
    
    }
    func freeBufferedFrames() {
        audioFrames.removeAllObjects()
        currentAudioFrame = nil
        if subtitles != nil {
            subtitles.removeAllObjects()
        }
        bufferedDuration = 0
    
    }
    func decodeFrames() -> Bool{
        var frames = NSArray()
        if self.decoder.validAudio {
            frames = self.decoder.decodeFrames(0)
        }
        if frames.count > 0 {
            return self.addFrames(frames as! [KxMovieFrame])
        }
        return false
    }
    func pause() {
        if !self.playing {
            return
        }
        self.playing = false
        self.enableAudio(false)
        
    }
    @IBAction func pre(sender: AnyObject) {
        if currentIndex > 0 {
            currentIndex--
            clear()
            initSongs(songsArray[currentIndex])
        }
        
    }
    
    @IBAction func next(sender: AnyObject) {
        if currentIndex < songsArray.count - 1 {
            currentIndex++
            clear()
            initSongs(songsArray[currentIndex])
        }
        
        //快进
        //self.setingMoviePosition(Float(self.moviePosition) + Float(10.0))
    }
    func clear() {
        self.pause()
        self.freeBufferedFrames()
        self.decoder.closeFile()
        
    }
    
}

