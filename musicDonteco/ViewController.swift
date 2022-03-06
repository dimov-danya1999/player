

import UIKit
import AVFoundation



final class ViewController: UIViewController {
  private let audioEngine = AVAudioEngine()
    var player = AVAudioPlayer()
    let slider = UISlider()
    
   
    @IBAction func oneMusic(_ sender: Any) {
        
        do {
            if let audioPath = Bundle.main.path(forResource: "1", ofType: "mp3") {
                try player = AVAudioPlayer(contentsOf: URL(fileURLWithPath: audioPath))
            }
        } catch {
                print("error")
            }
        self.player.play()
        }
        
    
    
    @IBAction func twoMusic(_ sender: Any) {
        
        do {
            if let audioPath =  Bundle.main.path(forResource: "2", ofType: "mp3") {
                try player = AVAudioPlayer(contentsOf: URL(fileURLWithPath: audioPath))
            }
        }catch {
            print("error")
        }
        self.player.play()
        
    }
    
    @IBAction func goPlay(_ sender: Any) {
    
        loopedPlayList.play()
    }
    
    @IBAction func stopMusic(_ sender: Any) {
        self.player.stop()
       
        
        
    }
    private lazy var loopedPlayList = LoopedPlayList(engine: audioEngine)
        

        
        override func viewDidLoad() {
        super.viewDidLoad()
        
        do {
          try configureAudioSession()
          try fillPlayList()
        } catch {
          print(error)
        }
        
        audioEngine.prepare()
      }
      
      override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        do {
          try audioEngine.start()
        
        } catch {
          print(error)
        }
      }
        
    }

    extension ViewController {
      
      private func configureAudioSession() throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: AVAudioSession.RouteSharingPolicy.longFormAudio)
        try AVAudioSession.sharedInstance().setActive(true, options: [])
      }
      
      private func fillPlayList() throws {
        for sampleName in ["1",
                           "2"]
        {
          let sampleURL = Bundle.main.url(forResource: sampleName, withExtension: "mp3")!
          try loopedPlayList.append(.init(forReading: sampleURL))
        }
      }
    }

    // MARK: -
    final class LoopedPlayList {
      private let chainedNodesPool: [ChainedNodes]
      private let chainedNodesPoolIterator: AnyIterator<ChainedNodes>
      private var currentChainedNodes: ChainedNodes!
      
      private var audioFiles: [AVAudioFile] = []
      private var audioFilesIterator: AnyIterator<AVAudioFile>
      private var currentPlayingAudioFile: AVAudioFile!
      
      private let crossFadeDuration: TimeInterval = 3.0
      private lazy var volumeInterval: Float = 0.1 / Float(crossFadeDuration)
      
      private(set) var isPlaying: Bool = false
      
      init(engine: AVAudioEngine) {
        chainedNodesPool = (0..<2).map { (_) in .init(engine: engine) }
        chainedNodesPoolIterator = chainedNodesPool.makeInfiniteLoopIterator(startFrom: chainedNodesPool.startIndex)
        audioFilesIterator = audioFiles.makeInfiniteLoopIterator(startFrom: audioFiles.startIndex)
      }
      
      func append(_ audioFile: AVAudioFile) {
        audioFiles.append(audioFile)
        
        let nextIndex: Array<AVAudioFile>.Index
        
        if let audioFile = currentPlayingAudioFile {
          guard let index = audioFiles.firstIndex(of: audioFile) else { preconditionFailure() }
          nextIndex = audioFiles.index(after: index)
        } else {
          nextIndex = audioFiles.startIndex
        }
        
        audioFilesIterator = audioFiles.makeInfiniteLoopIterator(startFrom: nextIndex)
      }
      
      func play() {
        isPlaying = true
        playNext()
      }
       
      
      private func playNext() {
        guard let chainedNodes = chainedNodesPoolIterator.next(),
              let audioFile = audioFilesIterator.next()
        else { preconditionFailure() }
        
        let prevChainedNodes = currentChainedNodes

        currentChainedNodes = chainedNodes
        currentPlayingAudioFile = audioFile
        
        if prevChainedNodes == nil {
          currentChainedNodes.mixerVolume = 1.0
        } else {
          currentChainedNodes.mixerVolume = 0.0
        }
        
        currentChainedNodes.play(audioFile) { [_prevChainedNodes = currentChainedNodes] in
          DispatchQueue.main.async {
            // Stop prev audio node
            _prevChainedNodes?.stop()
          }
        }
        
        // We dont want start crossFade timer when we only start playing
        if let prevChainedNodes = prevChainedNodes {
          // Timer to change volumes on crossFade
          Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [self] (timer) in
            let currentVolume = prevChainedNodes.mixerVolume
            let newVolume = max(currentVolume - volumeInterval, 0.0)
            
            prevChainedNodes.mixerVolume = newVolume
            currentChainedNodes.mixerVolume = 1.0 - newVolume
            
            if newVolume == 0.0 { timer.invalidate() }
          }
        }
        
        // Timer to start playing next song on crossFade
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] (timer) in
          guard currentPlayingAudioFile.duration - currentChainedNodes.currentTime <= crossFadeDuration else { return }
          defer { playNext() }
          timer.invalidate()
        }
      }
    }

    extension LoopedPlayList {
      private final class ChainedNodes {
        private let auidoPlayer = AVAudioPlayerNode()
        private let mixer = AVAudioMixerNode()
        
        var mixerVolume: Float {
          get { mixer.volume }
          set { mixer.volume = newValue}
        }
        var currentTime: TimeInterval { auidoPlayer.currentTime }
        
        init(engine: AVAudioEngine) {
          attach(to: engine)
          connect(by: engine)
        }
            
        func play(_ audioFile: AVAudioFile, onEnd completionHandler: @escaping () -> Void) {
          auidoPlayer.scheduleFile(audioFile, at: nil, completionHandler: completionHandler)
          auidoPlayer.play()
        }
        
        func stop() {
          auidoPlayer.stop()
        
        }
        
        private func attach(to engine: AVAudioEngine) {
          engine.attach(auidoPlayer)
          engine.attach(mixer)
        }
        
        private func connect(by engine: AVAudioEngine) {
          engine.connect(auidoPlayer, to: mixer, format: nil)
          engine.connect(mixer, to: engine.mainMixerNode, format: nil)
        }
      }
    }

    // MARK: -
    extension AVAudioPlayerNode {
      var currentTime: TimeInterval {
        if let nodeTime = lastRenderTime, let playerTime = playerTime(forNodeTime: nodeTime) {
          return Double(playerTime.sampleTime) / playerTime.sampleRate
        } else {
          return 0.0
        }
      }
    }

    // MARK: -
    extension AVAudioFile {
      var duration: TimeInterval { Double(length) / processingFormat.sampleRate }
    }

    // MARK: -
    extension Array {
      func makeInfiniteLoopIterator(startFrom startIndex: Index) -> AnyIterator<Element> {
        var index = startIndex
        
        return .init {
          if isEmpty {
            return nil
          }
          
          let result = self[index]
          
          index = self.index(after: index)
          if index == endIndex {
            index = startIndex
          }
          
          return result
        }
      }
    }
    
    
    


