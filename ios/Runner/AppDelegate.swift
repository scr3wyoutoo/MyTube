import AVFoundation
import AVKit
import Flutter
import MediaPlayer
import QuartzCore
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "IosPictureInPicturePlugin"
    ) {
      IosPictureInPicturePlugin.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "IosNativeAudioPlaybackPlugin"
    ) {
      IosNativeAudioPlaybackPlugin.register(with: registrar)
    }
  }
}

fileprivate final class IosNativePlayerView: UIView {
  override class var layerClass: AnyClass { AVPlayerLayer.self }

  var playerLayer: AVPlayerLayer {
    layer as! AVPlayerLayer
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    backgroundColor = .black
    playerLayer.videoGravity = .resizeAspect
    playerLayer.backgroundColor = UIColor.black.cgColor
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

fileprivate final class IosNativePlayerPlatformView: NSObject, FlutterPlatformView {
  private let nativeView: IosNativePlayerView
  private weak var plugin: IosPictureInPicturePlugin?

  init(frame: CGRect, plugin: IosPictureInPicturePlugin) {
    nativeView = IosNativePlayerView(frame: frame)
    self.plugin = plugin
    super.init()
    plugin.attachMainPlayerView(nativeView)
  }

  func view() -> UIView { nativeView }

  deinit {
    plugin?.detachMainPlayerView(nativeView)
  }
}

fileprivate final class IosNativePlayerViewFactory: NSObject, FlutterPlatformViewFactory {
  private let plugin: IosPictureInPicturePlugin

  init(plugin: IosPictureInPicturePlugin) {
    self.plugin = plugin
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    IosNativePlayerPlatformView(frame: frame, plugin: plugin)
  }
}

fileprivate final class IosPictureInPicturePlugin: NSObject, FlutterPlugin,
  AVPictureInPictureControllerDelegate
{
  private let channel: FlutterMethodChannel
  private weak var viewController: UIViewController?
  private var player: AVPlayer?
  private var nextPlayer: AVPlayer?
  private var nextConfiguredUrl: URL?
  private var nextTitle = ""
  private var nextArtist = ""
  private var nextThumbnailUrl = ""
  private var nextHasNextItem = false
  private var nextIsLive = false
  private var nextCrossfadeStarted = false
  private var periodicTimeObserver: Any?
  private var timeControlObservation: NSKeyValueObservation?
  private var completionObserver: NSObjectProtocol?
  private var playerLayer: AVPlayerLayer?
  private var pictureInPictureController: AVPictureInPictureController?
  private var prewarmRetry: DispatchWorkItem?
  private var prewarmAttempts = 0
  private let maxPrewarmAttempts = 50
  private var playerPrewarmed = false
  private var automaticStartArmed = false
  private var automaticStartTimeout: DispatchWorkItem?
  private var startRetry: DispatchWorkItem?
  private var pendingStartResult: FlutterResult?
  private var startAttempts = 0
  private var maxStartAttempts = 150
  private var notifyFailureForCurrentStart = true
  private var requestedPlaying = false
  private var autoEnterEnabled = false
  private var nativePlaybackActive = false
  private var restoreRequested = false
  private var wasPlayingBeforeStop = false
  private var title = ""
  private var artist = ""
  private var thumbnailUrl = ""
  private var artwork: MPMediaItemArtwork?
  private var configuredUrl: URL?
  private var remoteCommandTargets: [(MPRemoteCommand, Any)] = []
  private var playbackVolume: Float = 1
  private var playlistFadeEnabled = false
  private var hasNextItem = false
  private var isLive = false
  private let playlistFadeDuration = 5.0
  private var wasPlayingBeforeAudioInterruption = false
  private var currentDebugRequestId = 0
  private var delegateAwaitingDebugRequestId = 0
  private var lastDelegateDebugRequestId = 0
  private var nativeStartInvocationCount = 0
  private var lastDelegateEvent = "none"
  private var lastDelegateErrorDomain = ""
  private var lastDelegateErrorCode = 0
  private var lastDelegateErrorDescription = ""
  private var lastStartCollision = false
  private var debugResolution = ""
  private var debugTransport = ""
  private var debugIsHls = false
  private var debugHasHlsMaster = false
  private var debugHasSeparateAudio = false
  private var debugUsesProxy = false
  private var debugSourceScheme = ""
  private var debugSourcePath = ""
  private var debugMime = ""
  private var debugContentLength = 0
  private var hlsProbePlayer: AVPlayer?
  private var hlsProbeLayer: AVPlayerLayer?
  private var hlsProbeController: AVPictureInPictureController?
  private var hlsProbePoll: DispatchWorkItem?
  private var hlsProbeResult: FlutterResult?
  private var hlsProbeStartedAt = Date()
  private var hlsProbeTimeoutMilliseconds = 12_000
  private var hlsProbeToken = 0
  private var hlsProbeMutedPlaybackStarted = false
  private var hlsProbeItemReadyAtMilliseconds: Int64 = -1
  private var hlsProbeLayerReadyAtMilliseconds: Int64 = -1
  private var hlsProbePossibleAtMilliseconds: Int64 = -1
  private weak var mainPlayerView: IosNativePlayerView?
  private var mainPlayerMode = false
  private var mainPlayerOpenResult: FlutterResult?
  private var mainPlayerOpenPoll: DispatchWorkItem?
  private var mainPlayerOpenAttempts = 0
  private var lastMainStatePublishTime = Date.distantPast
  private var mainPlayerPictureInPictureEnabled = true
  private var mainPlayerContinuesAudioInBackground = false
  private var mainPlayerSeekGeneration = 0

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "flutter_browser_app/ios_picture_in_picture",
      binaryMessenger: registrar.messenger()
    )
    let instance = IosPictureInPicturePlugin(
      channel: channel,
      viewController: registrar.viewController
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.register(
      IosNativePlayerViewFactory(plugin: instance),
      withId: "flutter_browser_app/ios_native_player_view"
    )
  }

  private init(channel: FlutterMethodChannel, viewController: UIViewController?) {
    self.channel = channel
    self.viewController = viewController
    super.init()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAudioRouteChange(_:)),
      name: AVAudioSession.routeChangeNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAudioInterruption(_:)),
      name: AVAudioSession.interruptionNotification,
      object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        result(false)
        return
      }
      switch call.method {
      case "openMainPlayer":
        self.openMainPlayer(call.arguments, result: result)
      case "configure":
        self.configure(call.arguments, result: result)
      case "configureNext":
        self.configureNext(call.arguments, result: result)
      case "clearNext":
        self.clearNextPlayer()
        result(nil)
      case "start":
        self.start(call.arguments, result: result)
      case "armAutoEnter":
        self.armAutoEnter(call.arguments, result: result)
      case "cancelAutoEnter":
        self.cancelAutoEnter()
        result(nil)
      case "readDebugState":
        result(self.readDebugState(call.arguments))
      case "testHlsReadiness":
        self.testHlsReadiness(call.arguments, result: result)
      case "setVolume":
        self.setVolume(call.arguments)
        result(nil)
      case "setAutoEnterEnabled":
        self.setAutoEnterEnabled(call.arguments)
        result(nil)
      case "pause":
        self.pauseNativePlayback()
        result(nil)
      case "play":
        self.resumeNativePlayback()
        result(nil)
      case "seek":
        self.seekNativePlayback(call.arguments)
        result(nil)
      case "stop":
        self.pictureInPictureController?.stopPictureInPicture()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  fileprivate func attachMainPlayerView(_ view: IosNativePlayerView) {
    mainPlayerView = view
    guard mainPlayerMode, let player else { return }
    installMainPlayerLayer(view.playerLayer, player: player)
  }

  fileprivate func detachMainPlayerView(_ view: IosNativePlayerView) {
    guard mainPlayerView === view else { return }
    mainPlayerView = nil
    view.playerLayer.player = nil
  }

  @objc private func handleAudioRouteChange(_ notification: Notification) {
    guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
      let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
      reason == .oldDeviceUnavailable,
      let previousRoute = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey]
        as? AVAudioSessionRouteDescription,
      previousRoute.outputs.contains(where: isPrivateAudioOutput)
    else { return }

    if nativePlaybackActive {
      pauseNativePlayback()
    }
    channel.invokeMethod("pausedByAudioRouteChange", arguments: nil)
  }

  private func isPrivateAudioOutput(_ output: AVAudioSessionPortDescription) -> Bool {
    switch output.portType {
    case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .carAudio, .headphones, .airPlay:
      return true
    default:
      return false
    }
  }

  @objc private func handleAudioInterruption(_ notification: Notification) {
    guard nativePlaybackActive,
      let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: typeValue)
    else { return }

    switch type {
    case .began:
      wasPlayingBeforeAudioInterruption = player?.timeControlStatus == .playing
      pauseNativePlayback()
    case .ended:
      let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
      let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
      if wasPlayingBeforeAudioInterruption && options.contains(.shouldResume) {
        resumeNativePlayback()
      }
      wasPlayingBeforeAudioInterruption = false
    @unknown default:
      break
    }
  }

  private func pauseNativePlayback() {
    guard nativePlaybackActive else { return }
    requestedPlaying = false
    player?.pause()
    nextPlayer?.pause()
    updateNowPlayingInfo()
    publishMainPlayerState(force: true)
  }

  private func resumeNativePlayback() {
    guard nativePlaybackActive else { return }
    do {
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      return
    }
    requestedPlaying = true
    player?.play()
    if nextCrossfadeStarted {
      nextPlayer?.play()
    }
    updateNowPlayingInfo()
    publishMainPlayerState(force: true)
  }

  private func seekNativePlayback(_ rawArguments: Any?) {
    guard mainPlayerMode, !isLive, let player else { return }
    let arguments = rawArguments as? [String: Any]
    let milliseconds = arguments?["positionMilliseconds"] as? Int64
      ?? Int64(arguments?["positionMilliseconds"] as? Int ?? 0)
    mainPlayerSeekGeneration += 1
    let seekGeneration = mainPlayerSeekGeneration
    player.seek(
      to: CMTime(value: max(0, milliseconds), timescale: 1000),
      toleranceBefore: .zero,
      toleranceAfter: .zero
    ) { [weak self, weak player] finished in
      DispatchQueue.main.async {
        guard let self, let player, finished,
          self.mainPlayerMode,
          self.player === player,
          self.mainPlayerSeekGeneration == seekGeneration
        else { return }
        // A seek does not change the user's play/pause intent. Reconcile the
        // reused AVPlayer after the HLS seek has actually completed, then
        // publish a fresh state so Flutter can remove its loading indicator.
        self.applyRequestedMainPlayerPlaybackState(player)
        self.publishMainPlayerState(force: true)
      }
    }
    publishMainPlayerState(force: true)
  }

  private func openMainPlayer(_ rawArguments: Any?, result: @escaping FlutterResult) {
    guard let arguments = rawArguments as? [String: Any],
      let urlString = arguments["streamUrl"] as? String,
      let url = URL(string: urlString)
    else {
      result(false)
      return
    }

    guard let mainPlayerView else {
      result(
        FlutterError(
          code: "native_player_surface_unavailable",
          message: "The native iOS player surface is not attached.",
          details: nil
        )
      )
      return
    }

    mainPlayerOpenPoll?.cancel()
    mainPlayerOpenPoll = nil
    if let pendingResult = mainPlayerOpenResult {
      mainPlayerOpenResult = nil
      pendingResult(false)
    }

    mainPlayerMode = true
    nativePlaybackActive = true
    automaticStartArmed = false
    title = arguments["title"] as? String ?? ""
    artist = arguments["artist"] as? String ?? ""
    playbackVolume = Float(min(max(arguments["playbackVolume"] as? Double ?? 1, 0), 1))
    isLive = arguments["isLive"] as? Bool == true
    autoEnterEnabled = arguments["autoEnterEnabled"] as? Bool == true
    mainPlayerPictureInPictureEnabled =
      arguments["pictureInPictureEnabled"] as? Bool == true
    mainPlayerContinuesAudioInBackground =
      arguments["continuesAudioInBackground"] as? Bool == true
    requestedPlaying = arguments["playing"] as? Bool == true
    playlistFadeEnabled = false
    hasNextItem = false
    let newThumbnailUrl = arguments["thumbnailUrl"] as? String ?? ""
    if newThumbnailUrl != thumbnailUrl {
      thumbnailUrl = newThumbnailUrl
      artwork = nil
    }

    let milliseconds = arguments["positionMilliseconds"] as? Int64
      ?? Int64(arguments["positionMilliseconds"] as? Int ?? 0)
    let item = AVPlayerItem(url: url)
    configuredUrl = url
    mainPlayerSeekGeneration += 1

    let activePlayer: AVPlayer
    if let existingPlayer = player {
      removePlayerObservers(from: existingPlayer)
      existingPlayer.replaceCurrentItem(with: item)
      activePlayer = existingPlayer
    } else {
      activePlayer = AVPlayer(playerItem: item)
      activePlayer.automaticallyWaitsToMinimizeStalling = true
      player = activePlayer
    }

    applyMainPlayerBackgroundPlaybackPolicy(to: activePlayer)

    installMainPlayerLayer(mainPlayerView.playerLayer, player: activePlayer)
    observeMainPlayer(activePlayer, item: item)
    activePlayer.isMuted = false
    activePlayer.volume = playbackVolume
    if !isLive && milliseconds > 0 {
      activePlayer.seek(
        to: CMTime(value: milliseconds, timescale: 1000),
        toleranceBefore: .zero,
        toleranceAfter: .zero
      )
    }
    if requestedPlaying {
      do {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try AVAudioSession.sharedInstance().setActive(true)
      } catch {
        // AVPlayer still gets a chance to start; its item error is reported below.
      }
    }
    applyRequestedMainPlayerPlaybackState(activePlayer)
    applyAutoEnterSetting()
    mainPlayerOpenResult = result
    mainPlayerOpenAttempts = 0
    pollMainPlayerOpen()
  }

  private func installMainPlayerLayer(_ layer: AVPlayerLayer, player: AVPlayer) {
    if playerLayer !== layer {
      playerLayer?.player = nil
      playerLayer?.removeFromSuperlayer()
      pictureInPictureController?.delegate = nil
      pictureInPictureController = nil
    }
    layer.videoGravity = .resizeAspect
    layer.backgroundColor = UIColor.black.cgColor
    layer.player = player
    playerLayer = layer
    if mainPlayerPictureInPictureEnabled,
      AVPictureInPictureController.isPictureInPictureSupported(),
      pictureInPictureController == nil
    {
      let controller = AVPictureInPictureController(playerLayer: layer)
      controller?.delegate = self
      pictureInPictureController = controller
    } else if !mainPlayerPictureInPictureEnabled,
      let controller = pictureInPictureController
    {
      if controller.isPictureInPictureActive {
        controller.stopPictureInPicture()
      }
      controller.delegate = nil
      pictureInPictureController = nil
    }
    applyAutoEnterSetting()
  }

  private func observeMainPlayer(_ player: AVPlayer, item: AVPlayerItem) {
    periodicTimeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
      queue: .main
    ) { [weak self] _ in
      self?.publishMainPlayerState()
    }
    observeCompletion(of: item)
    timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) {
      [weak self] _, _ in
      DispatchQueue.main.async {
        self?.publishMainPlayerState(force: true)
      }
    }
  }

  private func removePlayerObservers(from observedPlayer: AVPlayer) {
    if let periodicTimeObserver {
      observedPlayer.removeTimeObserver(periodicTimeObserver)
    }
    periodicTimeObserver = nil
    timeControlObservation?.invalidate()
    timeControlObservation = nil
    if let completionObserver {
      NotificationCenter.default.removeObserver(completionObserver)
      self.completionObserver = nil
    }
  }

  private func applyRequestedMainPlayerPlaybackState(_ activePlayer: AVPlayer) {
    guard mainPlayerMode, player === activePlayer else { return }
    if requestedPlaying {
      activePlayer.play()
    } else {
      activePlayer.pause()
    }
  }

  private func applyMainPlayerBackgroundPlaybackPolicy(to activePlayer: AVPlayer) {
    if #available(iOS 15.0, *) {
      activePlayer.audiovisualBackgroundPlaybackPolicy =
        mainPlayerContinuesAudioInBackground ? .continuesIfPossible : .automatic
    }
  }

  private func pollMainPlayerOpen() {
    guard mainPlayerMode, let player, let item = player.currentItem else {
      finishMainPlayerOpen(false)
      return
    }
    mainPlayerOpenAttempts += 1
    if item.status == .failed || player.status == .failed {
      let message = item.error?.localizedDescription
        ?? player.error?.localizedDescription
        ?? "The native iOS player rejected the stream."
      finishMainPlayerOpen(
        FlutterError(code: "native_player_load_failed", message: message, details: nil)
      )
      return
    }
    let presentationSize = item.presentationSize
    if item.status == .readyToPlay
      && presentationSize.width > 0
      && presentationSize.height > 0
    {
      // AVPlayer may return to a paused time-control state while a freshly
      // assigned HLS item changes from unknown to readyToPlay. Reconcile that
      // transition with the latest user intent. If the user paused while the
      // item was loading, requestedPlaying is already false and stays paused.
      applyRequestedMainPlayerPlaybackState(player)
      publishMainPlayerState(force: true)
      finishMainPlayerOpen(true)
      return
    }
    if mainPlayerOpenAttempts >= 150 {
      finishMainPlayerOpen(
        FlutterError(
          code: "native_player_load_timeout",
          message: "The native iOS player did not become ready in time.",
          details: nil
        )
      )
      return
    }
    let retry = DispatchWorkItem { [weak self] in self?.pollMainPlayerOpen() }
    mainPlayerOpenPoll = retry
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: retry)
  }

  private func finishMainPlayerOpen(_ value: Any) {
    mainPlayerOpenPoll?.cancel()
    mainPlayerOpenPoll = nil
    guard let result = mainPlayerOpenResult else { return }
    mainPlayerOpenResult = nil
    result(value)
  }

  private func configure(_ rawArguments: Any?, result: @escaping FlutterResult) {
    guard #available(iOS 14.0, *),
      AVPictureInPictureController.isPictureInPictureSupported()
    else {
      result(false)
      return
    }
    let arguments = rawArguments as? [String: Any]
    autoEnterEnabled = arguments?["autoEnterEnabled"] as? Bool == true
    guard arguments?["enabled"] as? Bool == true,
      let urlString = arguments?["streamUrl"] as? String,
      let url = URL(string: urlString)
    else {
      disable()
      result(false)
      return
    }

    clearNextPlayer()

    title = arguments?["title"] as? String ?? ""
    artist = arguments?["artist"] as? String ?? ""
    playbackVolume = Float(min(max(arguments?["playbackVolume"] as? Double ?? 1, 0), 1))
    playlistFadeEnabled = arguments?["playlistFadeEnabled"] as? Bool == true
    hasNextItem = arguments?["hasNextItem"] as? Bool == true
    isLive = arguments?["isLive"] as? Bool == true
    debugResolution = arguments?["debugResolution"] as? String ?? ""
    debugTransport = arguments?["debugTransport"] as? String ?? ""
    debugIsHls = arguments?["debugIsHls"] as? Bool == true
    debugHasHlsMaster = arguments?["debugHasHlsMaster"] as? Bool == true
    debugHasSeparateAudio = arguments?["debugHasSeparateAudio"] as? Bool == true
    debugUsesProxy = arguments?["debugUsesProxy"] as? Bool == true
    debugSourceScheme = arguments?["debugSourceScheme"] as? String ?? ""
    debugSourcePath = arguments?["debugSourcePath"] as? String ?? ""
    debugMime = arguments?["debugMime"] as? String ?? ""
    debugContentLength = arguments?["debugContentLength"] as? Int ?? 0
    let newThumbnailUrl = arguments?["thumbnailUrl"] as? String ?? ""
    if newThumbnailUrl != thumbnailUrl {
      thumbnailUrl = newThumbnailUrl
      artwork = nil
      loadArtwork(from: newThumbnailUrl)
    }

    if configuredUrl != url || player == nil {
      if nativePlaybackActive, let player {
        let item = AVPlayerItem(url: url)
        configuredUrl = url
        player.replaceCurrentItem(with: item)
        observeCompletion(of: item)
        updateNowPlayingInfo()
      } else {
        preparePlayer(url: url)
      }
    }
    applyPlaylistFadeVolume()
    if nativePlaybackActive {
      activateRemoteCommands()
    }
    applyAutoEnterSetting()
    result(player != nil && pictureInPictureController != nil)
  }

  private func testHlsReadiness(
    _ rawArguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard #available(iOS 14.0, *),
      AVPictureInPictureController.isPictureInPictureSupported()
    else {
      result([
        "outcome": "unsupported",
        "pipSupported": false,
      ])
      return
    }
    guard hlsProbeResult == nil else {
      result(
        FlutterError(
          code: "hls_probe_running",
          message: "Ein nativer HLS-Test läuft bereits.",
          details: nil
        )
      )
      return
    }
    guard let arguments = rawArguments as? [String: Any],
      let urlString = arguments["streamUrl"] as? String,
      let url = URL(string: urlString)
    else {
      result(
        FlutterError(
          code: "invalid_hls_probe_url",
          message: "Die lokale HLS-Testquelle fehlt.",
          details: nil
        )
      )
      return
    }

    cleanupHlsProbe()
    hlsProbeToken += 1
    let token = hlsProbeToken
    hlsProbeStartedAt = Date()
    let requestedTimeout = arguments["timeoutMilliseconds"] as? Int ?? 12_000
    hlsProbeTimeoutMilliseconds = min(max(requestedTimeout, 3_000), 20_000)
    hlsProbeMutedPlaybackStarted = false
    hlsProbeItemReadyAtMilliseconds = -1
    hlsProbeLayerReadyAtMilliseconds = -1
    hlsProbePossibleAtMilliseconds = -1
    hlsProbeResult = result

    let item = AVPlayerItem(url: url)
    let probePlayer = AVPlayer(playerItem: item)
    probePlayer.automaticallyWaitsToMinimizeStalling = true
    probePlayer.isMuted = true
    probePlayer.volume = 0

    let probeLayer = AVPlayerLayer(player: probePlayer)
    probeLayer.videoGravity = .resizeAspect
    if let hostView = resolveViewController()?.view {
      probeLayer.frame = hostView.bounds
      hostView.layer.insertSublayer(probeLayer, at: 0)
    }
    let probeController = AVPictureInPictureController(playerLayer: probeLayer)

    hlsProbePlayer = probePlayer
    hlsProbeLayer = probeLayer
    hlsProbeController = probeController
    guard probeController != nil else {
      finishHlsProbe(outcome: "controllerUnavailable")
      return
    }

    // AVPlayer.preroll is only legal after the player has reached
    // AVPlayer.Status.readyToPlay. Calling it immediately after creating an
    // HLS item can raise an Objective-C exception and terminate the app.
    // play() is safe while the item is still loading: AVPlayer enters its
    // waiting state and starts as soon as the manifest is ready. The probe
    // remains inaudible and behind the Flutter surface.
    hlsProbeMutedPlaybackStarted = true
    probePlayer.play()
    pollHlsProbe(token: token)
  }

  private func pollHlsProbe(token: Int) {
    guard token == hlsProbeToken,
      let probePlayer = hlsProbePlayer,
      let item = probePlayer.currentItem,
      let probeLayer = hlsProbeLayer,
      let probeController = hlsProbeController
    else { return }

    let elapsed = hlsProbeElapsedMilliseconds()
    let presentationSize = item.presentationSize
    let presentationReady = presentationSize.width > 0 && presentationSize.height > 0
    if item.status == .readyToPlay && hlsProbeItemReadyAtMilliseconds < 0 {
      hlsProbeItemReadyAtMilliseconds = elapsed
    }
    if probeLayer.isReadyForDisplay && hlsProbeLayerReadyAtMilliseconds < 0 {
      hlsProbeLayerReadyAtMilliseconds = elapsed
    }
    if probeController.isPictureInPicturePossible && hlsProbePossibleAtMilliseconds < 0 {
      hlsProbePossibleAtMilliseconds = elapsed
    }

    let fullyReady = item.status == .readyToPlay
      && presentationReady
      && probeLayer.isReadyForDisplay
      && probeController.isPictureInPicturePossible
    if fullyReady {
      finishHlsProbe(outcome: "ready")
      return
    }
    if item.status == .failed || probePlayer.status == .failed {
      finishHlsProbe(outcome: "failed")
      return
    }

    if elapsed >= Int64(hlsProbeTimeoutMilliseconds) {
      finishHlsProbe(outcome: "timeout")
      return
    }

    let poll = DispatchWorkItem { [weak self] in
      self?.pollHlsProbe(token: token)
    }
    hlsProbePoll = poll
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: poll)
  }

  private func finishHlsProbe(outcome: String) {
    guard let result = hlsProbeResult else {
      cleanupHlsProbe()
      return
    }
    let values = hlsProbeValues(outcome: outcome)
    hlsProbeResult = nil
    cleanupHlsProbe()
    result(values)
  }

  private func hlsProbeValues(outcome: String) -> [String: Any] {
    let probePlayer = hlsProbePlayer
    let item = probePlayer?.currentItem
    let probeLayer = hlsProbeLayer
    let probeController = hlsProbeController
    let presentationSize = item?.presentationSize ?? .zero
    let loadedRange = item?.loadedTimeRanges.last?.timeRangeValue
    let loadedEndSeconds = loadedRange.map {
      CMTimeGetSeconds(CMTimeRangeGetEnd($0))
    }
    let itemError: NSError?
    if let error = item?.error {
      itemError = error as NSError
    } else {
      itemError = nil
    }
    let playerError: NSError?
    if let error = probePlayer?.error {
      playerError = error as NSError
    } else {
      playerError = nil
    }
    let presentationWidth: Double = Double(presentationSize.width)
    let presentationHeight: Double = Double(presentationSize.height)

    var values = [String: Any]()
    values["outcome"] = outcome
    values["elapsedMs"] = hlsProbeElapsedMilliseconds()
    values["timeoutMs"] = hlsProbeTimeoutMilliseconds
    values["sourceType"] = "localHlsMaster"
    values["pipSupported"] = AVPictureInPictureController.isPictureInPictureSupported()
    values["normalPipActive"] = pictureInPictureController?.isPictureInPictureActive ?? false
    values["itemStatus"] = playerItemStatusName(item?.status)
    values["playerStatus"] = playerStatusName(probePlayer?.status)
    values["timeControlStatus"] = timeControlStatusName(probePlayer?.timeControlStatus)
    values["reasonForWaiting"] = probePlayer?.reasonForWaitingToPlay?.rawValue ?? ""
    values["loadingStrategy"] = "mutedPlayWithoutPreroll"
    values["prerollUsed"] = false
    values["mutedPlaybackStarted"] = hlsProbeMutedPlaybackStarted
    values["itemReadyAtMs"] = hlsProbeItemReadyAtMilliseconds
    values["layerReadyAtMs"] = hlsProbeLayerReadyAtMilliseconds
    values["pipPossibleAtMs"] = hlsProbePossibleAtMilliseconds
    values["likelyToKeepUp"] = item?.isPlaybackLikelyToKeepUp ?? false
    values["bufferEmpty"] = item?.isPlaybackBufferEmpty ?? false
    values["loadedRangesCount"] = item?.loadedTimeRanges.count ?? 0
    values["loadedRangeEndMs"] = safeMilliseconds(seconds: loadedEndSeconds)
    values["presentationWidth"] = presentationWidth
    values["presentationHeight"] = presentationHeight
    values["layerReady"] = probeLayer?.isReadyForDisplay ?? false
    values["layerHasSuperlayer"] = probeLayer?.superlayer != nil
    values["pipControllerExists"] = probeController != nil
    values["pipPossible"] = probeController?.isPictureInPicturePossible ?? false
    values["itemErrorDomain"] = itemError?.domain ?? ""
    values["itemErrorCode"] = itemError?.code ?? 0
    values["itemErrorDescription"] = shortDescription(
      itemError?.localizedDescription ?? ""
    )
    values["playerErrorDomain"] = playerError?.domain ?? ""
    values["playerErrorCode"] = playerError?.code ?? 0
    values["playerErrorDescription"] = shortDescription(
      playerError?.localizedDescription ?? ""
    )
    return values
  }

  private func hlsProbeElapsedMilliseconds() -> Int64 {
    Int64(max(0.0, Date().timeIntervalSince(hlsProbeStartedAt) * 1_000))
  }

  private func cleanupHlsProbe() {
    hlsProbePoll?.cancel()
    hlsProbePoll = nil
    hlsProbePlayer?.pause()
    hlsProbeLayer?.removeFromSuperlayer()
    hlsProbeController = nil
    hlsProbeLayer = nil
    hlsProbePlayer = nil
  }

  private func configureNext(_ rawArguments: Any?, result: @escaping FlutterResult) {
    guard player != nil,
      let arguments = rawArguments as? [String: Any],
      let urlString = arguments["streamUrl"] as? String,
      let url = URL(string: urlString)
    else {
      result(false)
      return
    }

    clearNextPlayer()
    let item = AVPlayerItem(url: url)
    let preparedPlayer = AVPlayer(playerItem: item)
    preparedPlayer.automaticallyWaitsToMinimizeStalling = true
    preparedPlayer.volume = 0
    preparedPlayer.isMuted = false
    nextPlayer = preparedPlayer
    nextConfiguredUrl = url
    nextTitle = arguments["title"] as? String ?? ""
    nextArtist = arguments["artist"] as? String ?? ""
    nextThumbnailUrl = arguments["thumbnailUrl"] as? String ?? ""
    nextHasNextItem = arguments["hasNextItem"] as? Bool == true
    nextIsLive = arguments["isLive"] as? Bool == true
    // AVPlayerItem begins loading while paused. Do not call preroll before
    // AVPlayer reaches readyToPlay; that can raise an Objective-C exception
    // for HLS items. Playback starts normally when the crossfade window opens.
    result(true)
  }

  @available(iOS 14.0, *)
  private func preparePlayer(url: URL) {
    disable(clearMetadata: false)
    configuredUrl = url

    let item = AVPlayerItem(url: url)
    let newPlayer = AVPlayer(playerItem: item)
    newPlayer.automaticallyWaitsToMinimizeStalling = true
    newPlayer.isMuted = true
    newPlayer.volume = 0

    let layer = AVPlayerLayer(player: newPlayer)
    layer.videoGravity = .resizeAspect
    layer.backgroundColor = UIColor.black.cgColor
    layer.masksToBounds = true

    let controller = AVPictureInPictureController(playerLayer: layer)
    controller?.delegate = self
    if #available(iOS 14.2, *) {
      controller?.canStartPictureInPictureAutomaticallyFromInline = autoEnterEnabled
    }

    player = newPlayer
    periodicTimeObserver = newPlayer.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
      queue: .main
    ) { [weak self] _ in
      self?.applyPlaylistFadeVolume()
    }
    observeCompletion(of: item)
    timeControlObservation = newPlayer.observe(\.timeControlStatus, options: [.new]) {
      [weak self] _, _ in
      DispatchQueue.main.async {
        self?.updateNowPlayingInfo()
        self?.publishPlaybackState()
      }
    }
    playerLayer = layer
    pictureInPictureController = controller
    updateNativeLayerPlacement()
    beginPlayerPrewarm()
  }

  private func setAutoEnterEnabled(_ rawArguments: Any?) {
    let arguments = rawArguments as? [String: Any]
    autoEnterEnabled = arguments?["enabled"] as? Bool == true
    applyAutoEnterSetting()
    if !autoEnterEnabled && automaticStartArmed {
      cancelAutoEnter()
    }
  }

  private func applyAutoEnterSetting() {
    if #available(iOS 14.2, *) {
      pictureInPictureController?.canStartPictureInPictureAutomaticallyFromInline =
        autoEnterEnabled
    }
  }

  private func updateNativeLayerPlacement() {
    // Legacy shadow players are deliberately never inserted into Flutter's
    // root rendering hierarchy. Production video uses IosNativePlayerView as its one and
    // only inline AVPlayerLayer.
  }

  private func detachNativeLayerFromInlineSurface() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    playerLayer?.removeFromSuperlayer()
    CATransaction.commit()
  }

  private func beginPlayerPrewarm() {
    prewarmRetry?.cancel()
    prewarmRetry = nil
    prewarmAttempts = 0
    playerPrewarmed = false
    guard let player else { return }

    updateNativeLayerPlacement()
    player.isMuted = true
    player.play()
    pollPlayerPrewarm()
  }

  private func pollPlayerPrewarm() {
    guard let player,
      let item = player.currentItem,
      let layer = playerLayer,
      let controller = pictureInPictureController,
      !nativePlaybackActive,
      !automaticStartArmed
    else {
      prewarmRetry = nil
      return
    }

    updateNativeLayerPlacement()
    prewarmAttempts += 1
    let presentationSize = item.presentationSize
    let presentationReady = presentationSize.width > 0 && presentationSize.height > 0
    let fullyReady = item.status == .readyToPlay
      && presentationReady
      && layer.isReadyForDisplay
      && controller.isPictureInPicturePossible
    if fullyReady {
      finishPlayerPrewarm(ready: true)
      return
    }
    if item.status == .failed || player.status == .failed || prewarmAttempts >= maxPrewarmAttempts {
      finishPlayerPrewarm(ready: false)
      return
    }

    let retry = DispatchWorkItem { [weak self] in
      self?.pollPlayerPrewarm()
    }
    prewarmRetry = retry
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: retry)
  }

  private func finishPlayerPrewarm(ready: Bool) {
    prewarmRetry?.cancel()
    prewarmRetry = nil
    player?.pause()
    player?.isMuted = true
    if ready && !isLive {
      player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    playerPrewarmed = ready
  }

  private func armAutoEnter(_ rawArguments: Any?, result: @escaping FlutterResult) {
    guard #available(iOS 14.2, *),
      autoEnterEnabled,
      let player,
      let controller = pictureInPictureController
    else {
      result(false)
      return
    }
    let arguments = rawArguments as? [String: Any]
    let playing = arguments?["playing"] as? Bool == true
    guard playing, !controller.isPictureInPictureActive else {
      result(controller.isPictureInPictureActive)
      return
    }

    let milliseconds = arguments?["positionMilliseconds"] as? Int64
      ?? Int64(arguments?["positionMilliseconds"] as? Int ?? 0)
    let seekToPosition = arguments?["seekToPosition"] as? Bool ?? true
    prewarmRetry?.cancel()
    prewarmRetry = nil
    automaticStartTimeout?.cancel()
    automaticStartTimeout = nil
    updateNativeLayerPlacement()
    requestedPlaying = true
    automaticStartArmed = true
    player.isMuted = true
    if seekToPosition {
      player.seek(
        to: CMTime(value: milliseconds, timescale: 1000),
        toleranceBefore: .zero,
        toleranceAfter: .zero
      )
    }
    player.play()

    let timeout = DispatchWorkItem { [weak self] in
      guard let self,
        self.automaticStartArmed,
        self.pictureInPictureController?.isPictureInPictureActive != true
      else { return }
      self.cancelAutoEnter(notifyFlutter: true)
    }
    automaticStartTimeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: timeout)
    result(true)
  }

  private func cancelAutoEnter(notifyFlutter: Bool = false) {
    guard automaticStartArmed,
      pictureInPictureController?.isPictureInPictureActive != true
    else { return }
    automaticStartTimeout?.cancel()
    automaticStartTimeout = nil
    automaticStartArmed = false
    requestedPlaying = false
    player?.pause()
    player?.isMuted = true
    nativePlaybackActive = false
    detachNativeLayerFromInlineSurface()
    if notifyFlutter {
      channel.invokeMethod("autoEnterCancelled", arguments: nil)
    }
  }

  private func start(_ rawArguments: Any?, result: @escaping FlutterResult) {
    guard #available(iOS 14.0, *), let player, pictureInPictureController != nil else {
      result(false)
      return
    }
    if mainPlayerMode {
      if pendingStartResult != nil {
        result(false)
        return
      }
      let arguments = rawArguments as? [String: Any]
      notifyFailureForCurrentStart = arguments?["notifyFailure"] as? Bool ?? true
      currentDebugRequestId = arguments?["debugRequestId"] as? Int ?? 0
      requestedPlaying = player.timeControlStatus == .playing
      nativePlaybackActive = true
      pendingStartResult = result
      startAttempts = 0
      maxStartAttempts = 50
      attemptStart()
      return
    }
    if pendingStartResult != nil {
      result(false)
      return
    }
    prewarmRetry?.cancel()
    prewarmRetry = nil
    automaticStartTimeout?.cancel()
    automaticStartTimeout = nil
    automaticStartArmed = false
    updateNativeLayerPlacement()
    let arguments = rawArguments as? [String: Any]
    currentDebugRequestId = arguments?["debugRequestId"] as? Int ?? 0
    lastStartCollision = false
    lastDelegateEvent = "none"
    lastDelegateDebugRequestId = 0
    lastDelegateErrorDomain = ""
    lastDelegateErrorCode = 0
    lastDelegateErrorDescription = ""
    let milliseconds = arguments?["positionMilliseconds"] as? Int64
      ?? Int64(arguments?["positionMilliseconds"] as? Int ?? 0)
    requestedPlaying = arguments?["playing"] as? Bool == true
    let seekToPosition = arguments?["seekToPosition"] as? Bool ?? true
    notifyFailureForCurrentStart = arguments?["notifyFailure"] as? Bool ?? true
    let readinessTimeoutMilliseconds = min(
      max(arguments?["readinessTimeoutMilliseconds"] as? Int ?? 15_000, 1_000),
      15_000
    )
    maxStartAttempts = max(10, readinessTimeoutMilliseconds / 100)
    nativePlaybackActive = true
    restoreRequested = false
    startAttempts = 0

    let position = CMTime(value: milliseconds, timescale: 1000)
    if seekToPosition {
      player.seek(to: position, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    applyPlaylistFadeVolume()
    player.isMuted = true
    player.play()
    pendingStartResult = result
    attemptStart()
  }

  private func attemptStart() {
    guard #available(iOS 14.0, *),
      let player,
      let controller = pictureInPictureController
    else {
      completePendingStart(false)
      return
    }

    startAttempts += 1
    if player.currentItem?.status == .failed {
      startRetry?.cancel()
      startRetry = nil
      if !mainPlayerMode {
        player.pause()
        player.isMuted = true
        nativePlaybackActive = false
        deactivateRemoteCommands()
      }
      lastDelegateEvent = "failedToStart"
      lastDelegateDebugRequestId = currentDebugRequestId
      completePendingStart(false)
      publishStartFailure("Der native iOS-Player konnte das Medium nicht laden.")
      return
    }

    let itemReady = player.currentItem?.status == .readyToPlay
    let layerReady = playerLayer?.isReadyForDisplay == true
    if controller.isPictureInPictureActive, itemReady {
      if !requestedPlaying {
        player.pause()
      }
      player.isMuted = mainPlayerMode ? false : !requestedPlaying
      if !mainPlayerMode {
        applyPlaylistFadeVolume()
        activateRemoteCommands()
        updateNowPlayingInfo()
      }
      completePendingStart(true)
      return
    }
    if itemReady && layerReady && controller.isPictureInPicturePossible {
      nativeStartInvocationCount += 1
      if delegateAwaitingDebugRequestId == 0 {
        delegateAwaitingDebugRequestId = currentDebugRequestId
      } else {
        lastStartCollision = true
      }
      controller.startPictureInPicture()
      return
    }

    if startAttempts >= maxStartAttempts {
      startRetry = nil
      if !mainPlayerMode {
        player.pause()
        nextPlayer?.pause()
        player.isMuted = true
        nativePlaybackActive = false
        deactivateRemoteCommands()
      }
      lastDelegateEvent = "retryTimeout"
      lastDelegateDebugRequestId = currentDebugRequestId
      delegateAwaitingDebugRequestId = 0
      publishStartFailure(
        "Der native iOS-Player war nicht rechtzeitig für PiP bereit."
      )
      completePendingStart(false)
      return
    }
    let retry = DispatchWorkItem { [weak self] in self?.attemptStart() }
    startRetry = retry
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: retry)
  }

  private func disable(clearMetadata: Bool = true) {
    mainPlayerSeekGeneration += 1
    mainPlayerOpenPoll?.cancel()
    mainPlayerOpenPoll = nil
    finishMainPlayerOpen(false)
    prewarmRetry?.cancel()
    prewarmRetry = nil
    automaticStartTimeout?.cancel()
    automaticStartTimeout = nil
    startRetry?.cancel()
    startRetry = nil
    completePendingStart(false)
    if pictureInPictureController?.isPictureInPictureActive == true {
      pictureInPictureController?.stopPictureInPicture()
    }
    player?.pause()
    clearNextPlayer()
    nativePlaybackActive = false
    automaticStartArmed = false
    playerPrewarmed = false
    if let player {
      removePlayerObservers(from: player)
    }
    mainPlayerView?.playerLayer.player = nil
    playerLayer?.removeFromSuperlayer()
    playerLayer = nil
    pictureInPictureController?.delegate = nil
    pictureInPictureController = nil
    player = nil
    configuredUrl = nil
    mainPlayerMode = false
    mainPlayerContinuesAudioInBackground = false
    deactivateRemoteCommands(clearMetadata: clearMetadata)
  }

  private func clearNextPlayer() {
    nextPlayer?.pause()
    nextPlayer = nil
    nextConfiguredUrl = nil
    nextTitle = ""
    nextArtist = ""
    nextThumbnailUrl = ""
    nextHasNextItem = false
    nextIsLive = false
    nextCrossfadeStarted = false
  }

  private func completePendingStart(_ accepted: Bool) {
    guard let pendingStartResult else { return }
    self.pendingStartResult = nil
    pendingStartResult(accepted)
  }

  private func publishStartFailure(_ message: String) {
    guard notifyFailureForCurrentStart else { return }
    channel.invokeMethod("failed", arguments: message)
  }

  private func observeCompletion(of item: AVPlayerItem) {
    if let completionObserver {
      NotificationCenter.default.removeObserver(completionObserver)
    }
    completionObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self] _ in
      guard let self, self.nativePlaybackActive else { return }
      if self.mainPlayerMode {
        self.publishMainPlayerState(force: true)
        self.channel.invokeMethod("completed", arguments: nil)
        return
      }
      if self.nextCrossfadeStarted, self.nextPlayer != nil {
        self.promoteNextPlayer()
      } else {
        self.channel.invokeMethod("completed", arguments: nil)
      }
    }
  }

  private func promoteNextPlayer() {
    guard let oldPlayer = player,
      let promotedPlayer = nextPlayer,
      let item = promotedPlayer.currentItem
    else { return }

    if let periodicTimeObserver {
      oldPlayer.removeTimeObserver(periodicTimeObserver)
    }
    periodicTimeObserver = nil
    timeControlObservation?.invalidate()
    timeControlObservation = nil
    oldPlayer.pause()

    player = promotedPlayer
    playerLayer?.player = promotedPlayer
    configuredUrl = nextConfiguredUrl
    title = nextTitle
    artist = nextArtist
    let promotedThumbnailUrl = nextThumbnailUrl
    hasNextItem = nextHasNextItem
    isLive = nextIsLive
    nextPlayer = nil
    nextConfiguredUrl = nil
    nextTitle = ""
    nextArtist = ""
    nextThumbnailUrl = ""
    nextHasNextItem = false
    nextIsLive = false
    nextCrossfadeStarted = false

    if promotedThumbnailUrl != thumbnailUrl {
      thumbnailUrl = promotedThumbnailUrl
      artwork = nil
      loadArtwork(from: promotedThumbnailUrl)
    }
    periodicTimeObserver = promotedPlayer.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
      queue: .main
    ) { [weak self] _ in
      self?.applyPlaylistFadeVolume()
    }
    observeCompletion(of: item)
    timeControlObservation = promotedPlayer.observe(
      \.timeControlStatus,
      options: [.new]
    ) { [weak self] _, _ in
      DispatchQueue.main.async {
        self?.updateNowPlayingInfo()
        self?.publishPlaybackState()
      }
    }
    promotedPlayer.isMuted = false
    applyPlaylistFadeVolume()
    activateRemoteCommands()
    updateNowPlayingInfo()
    channel.invokeMethod("advanced", arguments: nil)
  }

  private func resolveViewController() -> UIViewController? {
    if let viewController { return viewController }
    let activeScene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
    return activeScene?.windows.first { $0.isKeyWindow }?.rootViewController
  }

  func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    prewarmRetry?.cancel()
    prewarmRetry = nil
    automaticStartTimeout?.cancel()
    automaticStartTimeout = nil
    automaticStartArmed = false
    startRetry?.cancel()
    startRetry = nil
    if !requestedPlaying {
      player?.pause()
    }
    player?.isMuted = false
    if !mainPlayerMode {
      applyPlaylistFadeVolume()
    }
    nativePlaybackActive = true
    lastDelegateEvent = "didStart"
    lastDelegateDebugRequestId = delegateAwaitingDebugRequestId
    delegateAwaitingDebugRequestId = 0
    lastDelegateErrorDomain = ""
    lastDelegateErrorCode = 0
    lastDelegateErrorDescription = ""
    completePendingStart(true)
    if !mainPlayerMode {
      activateRemoteCommands()
      updateNowPlayingInfo()
    }
    publishMainPlayerState(force: true)
    channel.invokeMethod("started", arguments: nil)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    let nativeError = error as NSError
    automaticStartTimeout?.cancel()
    automaticStartTimeout = nil
    automaticStartArmed = false
    if !mainPlayerMode {
      player?.pause()
      nextPlayer?.pause()
      player?.isMuted = true
      nativePlaybackActive = false
      detachNativeLayerFromInlineSurface()
    }
    lastDelegateEvent = "failedToStart"
    lastDelegateDebugRequestId = delegateAwaitingDebugRequestId
    delegateAwaitingDebugRequestId = 0
    lastDelegateErrorDomain = nativeError.domain
    lastDelegateErrorCode = nativeError.code
    lastDelegateErrorDescription = shortDescription(nativeError.localizedDescription)
    completePendingStart(false)
    if !mainPlayerMode {
      deactivateRemoteCommands()
    }
    publishStartFailure(error.localizedDescription)
  }

  func pictureInPictureControllerWillStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    wasPlayingBeforeStop = player?.timeControlStatus == .playing
  }

  func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    let position = safePositionMilliseconds()
    let shouldResume = restoreRequested && wasPlayingBeforeStop
    automaticStartTimeout?.cancel()
    automaticStartTimeout = nil
    automaticStartArmed = false
    let closedInBackground = !restoreRequested
      && UIApplication.shared.applicationState != .active
    if mainPlayerMode {
      if closedInBackground {
        requestedPlaying = false
        player?.pause()
      }
      player?.isMuted = false
      nativePlaybackActive = true
      publishMainPlayerState(force: true)
    } else {
      player?.pause()
      nextPlayer?.pause()
      player?.isMuted = true
      nativePlaybackActive = false
      detachNativeLayerFromInlineSurface()
      deactivateRemoteCommands()
    }
    lastDelegateEvent = "didStop"
    lastDelegateDebugRequestId = currentDebugRequestId
    completePendingStart(false)
    channel.invokeMethod(
      "stopped",
      arguments: [
        "positionMilliseconds": position,
        "shouldResume": shouldResume,
        "restoredUserInterface": restoreRequested,
      ]
    )
    restoreRequested = false
  }

  private func readDebugState(_ rawArguments: Any?) -> [String: Any] {
    let arguments = rawArguments as? [String: Any]
    let requestId = arguments?["requestId"] as? Int ?? currentDebugRequestId
    let checkpoint = arguments?["checkpoint"] as? String ?? "unknown"
    let trigger = arguments?["trigger"] as? String ?? "unknown"
    let item = player?.currentItem
    let layer = playerLayer
    let controller = pictureInPictureController
    let playerError: NSError?
    if let error = player?.error {
      playerError = error as NSError
    } else {
      playerError = nil
    }
    let itemError: NSError?
    if let error = item?.error {
      itemError = error as NSError
    } else {
      itemError = nil
    }
    let loadedRange = item?.loadedTimeRanges.last?.timeRangeValue
    let loadedEndSeconds = loadedRange.map { CMTimeGetSeconds(CMTimeRangeGetEnd($0)) }
    let presentationSize = item?.presentationSize ?? .zero
    let hostView = resolveViewController()?.view
    let sceneState = hostView?.window?.windowScene?.activationState
    var automaticInline = false
    if #available(iOS 14.2, *) {
      automaticInline = controller?.canStartPictureInPictureAutomaticallyFromInline ?? false
    }

    let playerRate: Double = Double(player?.rate ?? 0.0)
    let playerVolume: Double = Double(player?.volume ?? 0.0)
    let presentationWidth: Double = Double(presentationSize.width)
    let presentationHeight: Double = Double(presentationSize.height)
    let layerFrameWidth: Double = Double(layer?.frame.width ?? CGFloat.zero)
    let layerFrameHeight: Double = Double(layer?.frame.height ?? CGFloat.zero)
    let layerBoundsWidth: Double = Double(layer?.bounds.width ?? CGFloat.zero)
    let layerBoundsHeight: Double = Double(layer?.bounds.height ?? CGFloat.zero)
    let layerOpacity: Double = Double(layer?.opacity ?? 0.0)
    let layerPlayerAttached: Bool
    if let concreteLayer = layer, let concretePlayer = player {
      layerPlayerAttached = concreteLayer.player === concretePlayer
    } else {
      layerPlayerAttached = false
    }
    let retryObjectExists: Bool
    if let pendingRetry = startRetry {
      retryObjectExists = !pendingRetry.isCancelled
    } else {
      retryObjectExists = false
    }
    let sourceHostType: String = debugUsesProxy ? "loopback" : "remote"
    let layerAttachedToFlutterHostView: Bool
    if let concreteSuperlayer = layer?.superlayer,
      let hostLayer = hostView?.layer
    {
      layerAttachedToFlutterHostView = concreteSuperlayer === hostLayer
    } else {
      layerAttachedToFlutterHostView = false
    }

    var state = [String: Any]()
    state["requestId"] = requestId
    state["checkpoint"] = checkpoint
    state["trigger"] = trigger
    state["iosVersion"] = UIDevice.current.systemVersion
    state["applicationState"] = applicationStateName(UIApplication.shared.applicationState)
    state["sceneState"] = sceneActivationStateName(sceneState)
    state["pipSupported"] = AVPictureInPictureController.isPictureInPictureSupported()
    state["playerExists"] = player != nil
    state["itemExists"] = item != nil
    state["playerStatus"] = playerStatusName(player?.status)
    state["itemStatus"] = playerItemStatusName(item?.status)
    state["playerErrorDomain"] = playerError?.domain ?? ""
    state["playerErrorCode"] = playerError?.code ?? 0
    state["playerErrorDescription"] = shortDescription(
      playerError?.localizedDescription ?? ""
    )
    state["itemErrorDomain"] = itemError?.domain ?? ""
    state["itemErrorCode"] = itemError?.code ?? 0
    state["itemErrorDescription"] = shortDescription(
      itemError?.localizedDescription ?? ""
    )
    state["timeControlStatus"] = timeControlStatusName(player?.timeControlStatus)
    state["reasonForWaiting"] = player?.reasonForWaitingToPlay?.rawValue ?? ""
    state["rate"] = playerRate
    state["muted"] = player?.isMuted ?? false
    state["volume"] = playerVolume
    state["positionMs"] = safeMilliseconds(player?.currentTime())
    state["durationMs"] = safeMilliseconds(item?.duration)
    state["likelyToKeepUp"] = item?.isPlaybackLikelyToKeepUp ?? false
    state["bufferEmpty"] = item?.isPlaybackBufferEmpty ?? false
    state["bufferFull"] = item?.isPlaybackBufferFull ?? false
    state["loadedRangesCount"] = item?.loadedTimeRanges.count ?? 0
    state["loadedRangeEndMs"] = safeMilliseconds(seconds: loadedEndSeconds)
    state["presentationWidth"] = presentationWidth
    state["presentationHeight"] = presentationHeight
    state["layerExists"] = layer != nil
    state["layerReady"] = layer?.isReadyForDisplay ?? false
    state["layerPlayerAttached"] = layerPlayerAttached
    state["layerHasSuperlayer"] = layer?.superlayer != nil
    state["layerFrameWidth"] = layerFrameWidth
    state["layerFrameHeight"] = layerFrameHeight
    state["layerBoundsWidth"] = layerBoundsWidth
    state["layerBoundsHeight"] = layerBoundsHeight
    state["layerHidden"] = layer?.isHidden ?? false
    state["layerOpacity"] = layerOpacity
    state["hostWindowExists"] = hostView?.window != nil
    state["layerAttachedToFlutterHostView"] = layerAttachedToFlutterHostView
    state["controllerExists"] = controller != nil
    state["pipPossible"] = controller?.isPictureInPicturePossible ?? false
    state["pipActive"] = controller?.isPictureInPictureActive ?? false
    state["pipSuspended"] = controller?.isPictureInPictureSuspended ?? false
    state["automaticInline"] = automaticInline
    state["nativeStartInvocationCount"] = nativeStartInvocationCount
    state["startAttempts"] = startAttempts
    state["maxStartAttempts"] = maxStartAttempts
    state["notifyFailureForCurrentStart"] = notifyFailureForCurrentStart
    state["retryObjectExists"] = retryObjectExists
    state["delegateAwaitingRequestId"] = delegateAwaitingDebugRequestId
    state["lastDelegateEvent"] = lastDelegateEvent
    state["lastDelegateRequestId"] = lastDelegateDebugRequestId
    state["lastDelegateErrorDomain"] = lastDelegateErrorDomain
    state["lastDelegateErrorCode"] = lastDelegateErrorCode
    state["lastDelegateErrorDescription"] = lastDelegateErrorDescription
    state["lastStartCollision"] = lastStartCollision
    state["requestedPlaying"] = requestedPlaying
    state["nativePlaybackActive"] = nativePlaybackActive
    state["playerPrewarmed"] = playerPrewarmed
    state["automaticStartArmed"] = automaticStartArmed
    state["autoEnterEnabled"] = autoEnterEnabled
    state["restoreRequested"] = restoreRequested
    state["wasPlayingBeforeStop"] = wasPlayingBeforeStop
    state["nextPlayerExists"] = nextPlayer != nil
    state["debugResolution"] = debugResolution
    state["debugTransport"] = debugTransport
    state["debugIsHls"] = debugIsHls
    state["debugHasHlsMaster"] = debugHasHlsMaster
    state["debugHasSeparateAudio"] = debugHasSeparateAudio
    state["debugUsesProxy"] = debugUsesProxy
    state["debugSourceScheme"] = debugSourceScheme
    state["debugSourceHostType"] = sourceHostType
    state["debugSourcePath"] = debugSourcePath
    state["debugMime"] = debugMime
    state["debugContentLength"] = debugContentLength
    return state
  }

  private func safeMilliseconds(_ time: CMTime?) -> Int64 {
    guard let time else { return 0 }
    return safeMilliseconds(seconds: time.seconds)
  }

  private func safeMilliseconds(seconds: Double?) -> Int64 {
    guard let seconds, seconds.isFinite else { return 0 }
    return Int64(max(0, seconds * 1000))
  }

  private func shortDescription(_ description: String) -> String {
    if description.count <= 240 { return description }
    return String(description.prefix(240))
  }

  private func applicationStateName(_ state: UIApplication.State) -> String {
    switch state {
    case .active: return "active"
    case .inactive: return "inactive"
    case .background: return "background"
    @unknown default: return "unknown"
    }
  }

  private func sceneActivationStateName(_ state: UIScene.ActivationState?) -> String {
    switch state {
    case .foregroundActive: return "foregroundActive"
    case .foregroundInactive: return "foregroundInactive"
    case .background: return "background"
    case .unattached: return "unattached"
    case nil: return "none"
    @unknown default: return "unknown"
    }
  }

  private func playerStatusName(_ status: AVPlayer.Status?) -> String {
    switch status {
    case .unknown: return "unknown"
    case .readyToPlay: return "readyToPlay"
    case .failed: return "failed"
    case nil: return "none"
    @unknown default: return "unknownFuture"
    }
  }

  private func playerItemStatusName(_ status: AVPlayerItem.Status?) -> String {
    switch status {
    case .unknown: return "unknown"
    case .readyToPlay: return "readyToPlay"
    case .failed: return "failed"
    case nil: return "none"
    @unknown default: return "unknownFuture"
    }
  }

  private func timeControlStatusName(_ status: AVPlayer.TimeControlStatus?) -> String {
    switch status {
    case .paused: return "paused"
    case .waitingToPlayAtSpecifiedRate: return "waiting"
    case .playing: return "playing"
    case nil: return "none"
    @unknown default: return "unknownFuture"
    }
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler:
      @escaping (Bool) -> Void
  ) {
    restoreRequested = true
    resolveViewController()?.view.window?.makeKeyAndVisible()
    completionHandler(true)
  }

  private func safePositionMilliseconds() -> Int64 {
    guard let seconds = player?.currentTime().seconds, seconds.isFinite else { return 0 }
    return Int64(max(0, seconds * 1000))
  }

  private func setVolume(_ rawArguments: Any?) {
    let arguments = rawArguments as? [String: Any]
    playbackVolume = Float(min(max(arguments?["volume"] as? Double ?? 1, 0), 1))
    applyPlaylistFadeVolume()
  }

  private func applyPlaylistFadeVolume() {
    guard let player else { return }
    var factor = 1.0
    var incomingFactor = 0.0
    var fadeDuration = playlistFadeDuration
    if playlistFadeEnabled {
      let position = max(0, player.currentTime().seconds.isFinite
        ? player.currentTime().seconds : 0)
      let rawDuration = player.currentItem?.duration.seconds ?? 0
      let duration = rawDuration.isFinite ? max(0, rawDuration) : 0
      fadeDuration = duration > 0
        ? min(playlistFadeDuration, max(0.001, duration / 2))
        : playlistFadeDuration
      factor = min(1, position / fadeDuration)
      if hasNextItem, duration > 0 {
        let remaining = max(0, duration - position)
        factor = min(factor, min(1, remaining / fadeDuration))
        incomingFactor = max(0, min(1, 1 - (remaining / fadeDuration)))
      }
    }
    player.volume = playbackVolume * Float(factor)

    guard let nextPlayer else { return }
    nextPlayer.volume = playbackVolume * Float(incomingFactor)
    if incomingFactor <= 0 {
      if nextCrossfadeStarted {
        nextPlayer.pause()
        nextPlayer.seek(to: .zero)
        nextCrossfadeStarted = false
      }
      return
    }

    if !nextCrossfadeStarted {
      let elapsed = fadeDuration * incomingFactor
      nextPlayer.seek(
        to: CMTime(seconds: elapsed, preferredTimescale: 600),
        toleranceBefore: .zero,
        toleranceAfter: .zero
      )
      nextCrossfadeStarted = true
    }
    if player.timeControlStatus == .playing {
      nextPlayer.play()
    } else {
      nextPlayer.pause()
    }
  }

  private func activateRemoteCommands() {
    deactivateRemoteCommands(clearMetadata: false)
    let center = MPRemoteCommandCenter.shared()
    center.playCommand.isEnabled = true
    center.pauseCommand.isEnabled = true
    center.stopCommand.isEnabled = false
    center.changePlaybackPositionCommand.isEnabled = !isLive
    center.skipForwardCommand.isEnabled = !isLive
    center.skipForwardCommand.preferredIntervals = [10]
    center.skipBackwardCommand.isEnabled = !isLive
    center.skipBackwardCommand.preferredIntervals = [10]

    addTarget(center.playCommand) { [weak self] _ in
      self?.player?.play()
      if self?.nextCrossfadeStarted == true {
        self?.nextPlayer?.play()
      }
      self?.updateNowPlayingInfo()
      return .success
    }
    addTarget(center.pauseCommand) { [weak self] _ in
      self?.player?.pause()
      self?.nextPlayer?.pause()
      self?.updateNowPlayingInfo()
      return .success
    }
    if !isLive {
      addTarget(center.changePlaybackPositionCommand) { [weak self] event in
        guard let self,
          let event = event as? MPChangePlaybackPositionCommandEvent
        else { return .commandFailed }
        self.resetNextCrossfadeForSeek()
        self.player?.seek(to: CMTime(seconds: event.positionTime, preferredTimescale: 600))
        self.updateNowPlayingInfo()
        return .success
      }
      addTarget(center.skipForwardCommand) { [weak self] _ in
        self?.seekRelative(seconds: 10)
        return .success
      }
      addTarget(center.skipBackwardCommand) { [weak self] _ in
        self?.seekRelative(seconds: -10)
        return .success
      }
    }
  }

  private func addTarget(
    _ command: MPRemoteCommand,
    handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
  ) {
    let target = command.addTarget(handler: handler)
    remoteCommandTargets.append((command, target))
  }

  private func deactivateRemoteCommands(clearMetadata: Bool = true) {
    for (command, target) in remoteCommandTargets {
      command.removeTarget(target)
    }
    remoteCommandTargets.removeAll()
    if clearMetadata {
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
  }

  private func seekRelative(seconds: Double) {
    guard let player else { return }
    resetNextCrossfadeForSeek()
    let current = player.currentTime().seconds
    let duration = player.currentItem?.duration.seconds ?? 0
    let target = min(max(0, current + seconds), duration.isFinite ? duration : current + seconds)
    player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    updateNowPlayingInfo()
  }

  private func resetNextCrossfadeForSeek() {
    guard nextCrossfadeStarted else { return }
    nextPlayer?.pause()
    nextPlayer?.seek(to: .zero)
    nextPlayer?.volume = 0
    nextCrossfadeStarted = false
  }

  private func updateNowPlayingInfo() {
    guard nativePlaybackActive, let player else { return }
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: title,
      MPMediaItemPropertyArtist: artist,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime().seconds,
      MPNowPlayingInfoPropertyPlaybackRate: player.timeControlStatus == .playing ? 1.0 : 0.0,
    ]
    if let duration = player.currentItem?.duration.seconds, duration.isFinite {
      info[MPMediaItemPropertyPlaybackDuration] = duration
    }
    if let artwork {
      info[MPMediaItemPropertyArtwork] = artwork
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  private func publishPlaybackState() {
    guard nativePlaybackActive, let player else { return }
    if mainPlayerMode {
      publishMainPlayerState(force: true)
      return
    }
    channel.invokeMethod(
      "playbackStateChanged",
      arguments: ["playing": player.timeControlStatus == .playing]
    )
  }

  private func publishMainPlayerState(force: Bool = false) {
    guard mainPlayerMode, nativePlaybackActive, let player else { return }
    let now = Date()
    if !force && now.timeIntervalSince(lastMainStatePublishTime) < 0.2 {
      return
    }
    lastMainStatePublishTime = now
    let item = player.currentItem
    let size = item?.presentationSize ?? .zero
    let duration = safeMilliseconds(item?.duration)
    let timeControlStatus = player.timeControlStatus
    let waiting = timeControlStatus == .waitingToPlayAtSpecifiedRate
    let buffering = requestedPlaying
      && timeControlStatus != .playing
      && (waiting || item?.isPlaybackBufferEmpty == true)
    channel.invokeMethod(
      "playbackStateChanged",
      arguments: [
        "playing": player.timeControlStatus == .playing,
        "buffering": buffering,
        "positionMilliseconds": safePositionMilliseconds(),
        "durationMilliseconds": duration,
        "width": Int(max(0, size.width.rounded())),
        "height": Int(max(0, size.height.rounded())),
      ]
    )
  }

  private func loadArtwork(from urlString: String) {
    guard let url = URL(string: urlString) else { return }
    URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
      guard let self, self.thumbnailUrl == urlString,
        let data, let image = UIImage(data: data)
      else { return }
      DispatchQueue.main.async {
        self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        self.updateNowPlayingInfo()
      }
    }.resume()
  }
}

fileprivate struct IosNativeAudioMetadata {
  let title: String
  let artist: String
  let thumbnailUrl: String
  let hasNext: Bool
  let expectedDurationMilliseconds: Int64
}

/// Audio-only iOS backend. Exactly two AVPlayer instances live for the whole
/// playback session and alternate their active/standby roles after each
/// automatic crossfade. Replacing an AVPlayerItem never destroys either
/// player, so loading the following song cannot tear down the active output.
fileprivate final class IosNativeAudioPlaybackPlugin: NSObject, FlutterPlugin {
  private let channel: FlutterMethodChannel
  private let players = [AVPlayer(), AVPlayer()]
  private var activeIndex = 0
  private var activeMetadata = IosNativeAudioMetadata(
    title: "",
    artist: "",
    thumbnailUrl: "",
    hasNext: false,
    expectedDurationMilliseconds: 0
  )
  private var preparedMetadata: IosNativeAudioMetadata?
  private var preparedReady = false
  private var crossfadeStarted = false
  private var activeCompletionHandled = false
  private var requestedPlaying = false
  private var playbackVolume: Float = 1
  private var crossfadeDuration = 6.0
  private var hasPrevious = false
  private var hasNext = false
  private var remoteControlsEnabled = true
  private var activeTimeObserver: Any?
  private var activeTimeControlObservation: NSKeyValueObservation?
  private var activeItemStatusObservation: NSKeyValueObservation?
  private var completionObserver: NSObjectProtocol?
  private var openStatusObservation: NSKeyValueObservation?
  private var prepareStatusObservation: NSKeyValueObservation?
  private var openTimeout: DispatchWorkItem?
  private var prepareTimeout: DispatchWorkItem?
  private var pendingOpenResult: FlutterResult?
  private var pendingPrepareResult: FlutterResult?
  private var operationGeneration = 0
  private var remoteCommandTargets: [(MPRemoteCommand, Any)] = []
  private var artwork: MPMediaItemArtwork?
  private var artworkRequest = 0
  private var lastStatePublishTime = Date.distantPast
  private var playbackActive = false
  private var resumeAfterInterruption = false

  private var activePlayer: AVPlayer { players[activeIndex] }
  private var standbyPlayer: AVPlayer { players[1 - activeIndex] }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "flutter_browser_app/ios_native_audio_playback",
      binaryMessenger: registrar.messenger()
    )
    let instance = IosNativeAudioPlaybackPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    for player in players {
      player.automaticallyWaitsToMinimizeStalling = true
      player.volume = 0
      player.isMuted = false
    }
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAudioRouteChange(_:)),
      name: AVAudioSession.routeChangeNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAudioInterruption(_:)),
      name: AVAudioSession.interruptionNotification,
      object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    removeActiveObservers()
    deactivateRemoteCommands()
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        result(false)
        return
      }
      switch call.method {
      case "open":
        self.open(call.arguments, result: result)
      case "prepareNext":
        self.prepareNext(call.arguments, result: result)
      case "clearNext":
        self.clearPreparedNext(resolvePending: true)
        result(nil)
      case "updateNavigation":
        self.updateNavigation(call.arguments)
        result(nil)
      case "play":
        self.play()
        result(nil)
      case "pause":
        self.pause()
        result(nil)
      case "seek":
        self.seek(call.arguments)
        result(nil)
      case "setVolume":
        self.setVolume(call.arguments)
        result(nil)
      case "stop":
        self.stop()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func open(_ rawArguments: Any?, result: @escaping FlutterResult) {
    guard let arguments = rawArguments as? [String: Any],
      let urlString = arguments["streamUrl"] as? String,
      let url = URL(string: urlString)
    else {
      result(false)
      return
    }

    operationGeneration += 1
    let generation = operationGeneration
    finishOpen(false)
    clearPreparedNext(resolvePending: true)
    removeActiveObservers()
    activePlayer.pause()
    standbyPlayer.pause()
    standbyPlayer.replaceCurrentItem(with: nil)
    standbyPlayer.volume = 0

    activeMetadata = metadata(from: arguments)
    hasPrevious = arguments["hasPrevious"] as? Bool == true
    hasNext = arguments["hasNext"] as? Bool == true
    remoteControlsEnabled = arguments["remoteControlsEnabled"] as? Bool ?? true
    requestedPlaying = arguments["playing"] as? Bool == true
    playbackVolume = clampedVolume(arguments["volume"] as? Double ?? 1)
    let requestedMilliseconds = millisecondsValue(arguments["positionMilliseconds"])
    let nonnegativeMilliseconds = max(0, requestedMilliseconds)
    let milliseconds = activeMetadata.expectedDurationMilliseconds > 0
      ? min(nonnegativeMilliseconds, activeMetadata.expectedDurationMilliseconds)
      : nonnegativeMilliseconds
    crossfadeDuration = max(
      0.25,
      Double(millisecondsValue(arguments["crossfadeMilliseconds"])) / 1000.0
    )
    artwork = nil
    loadArtwork(from: activeMetadata.thumbnailUrl)

    let item = AVPlayerItem(url: url)
    item.preferredForwardBufferDuration = max(8, crossfadeDuration + 2)
    applyExpectedEndTime(to: item, metadata: activeMetadata)
    activePlayer.replaceCurrentItem(with: item)
    activePlayer.volume = playbackVolume
    playbackActive = true
    activeCompletionHandled = false
    configureAudioSession()
    installActiveObservers(item: item)
    if remoteControlsEnabled {
      activateRemoteCommands()
    } else {
      deactivateRemoteCommands()
    }
    updateNowPlayingInfo()

    let startPlayback = { [weak self] in
      guard let self, generation == self.operationGeneration else { return }
      if self.requestedPlaying {
        self.activePlayer.play()
      } else {
        self.activePlayer.pause()
      }
      self.publishState(force: true)
    }
    if milliseconds > 0 {
      activePlayer.seek(
        to: CMTime(value: milliseconds, timescale: 1000),
        toleranceBefore: .zero,
        toleranceAfter: .zero
      ) { _ in startPlayback() }
    } else {
      startPlayback()
    }

    pendingOpenResult = result
    openStatusObservation = item.observe(\.status, options: [.initial, .new]) {
      [weak self, weak item] _, _ in
      DispatchQueue.main.async {
        guard let self, let item, generation == self.operationGeneration else { return }
        switch item.status {
        case .readyToPlay:
          self.openStatusObservation?.invalidate()
          self.openStatusObservation = nil
          self.openTimeout?.cancel()
          self.openTimeout = nil
          startPlayback()
          self.finishOpen(true)
        case .failed:
          self.failActivePlayback(item.error?.localizedDescription)
          self.finishOpen(false)
        case .unknown:
          break
        @unknown default:
          break
        }
      }
    }
    let timeout = DispatchWorkItem { [weak self] in
      guard let self, generation == self.operationGeneration else { return }
      self.finishOpen(false)
      self.publishFailure("The native iOS audio player did not become ready in time.")
    }
    openTimeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
  }

  private func prepareNext(_ rawArguments: Any?, result: @escaping FlutterResult) {
    guard playbackActive,
      let arguments = rawArguments as? [String: Any],
      let urlString = arguments["streamUrl"] as? String,
      let url = URL(string: urlString)
    else {
      result(false)
      return
    }

    clearPreparedNext(resolvePending: true)
    let generation = operationGeneration
    preparedMetadata = metadata(from: arguments)
    let item = AVPlayerItem(url: url)
    item.preferredForwardBufferDuration = max(8, crossfadeDuration + 2)
    if let preparedMetadata {
      applyExpectedEndTime(to: item, metadata: preparedMetadata)
    }
    standbyPlayer.replaceCurrentItem(with: item)
    standbyPlayer.volume = 0
    standbyPlayer.isMuted = false
    pendingPrepareResult = result
    prepareStatusObservation = item.observe(\.status, options: [.initial, .new]) {
      [weak self, weak item] _, _ in
      DispatchQueue.main.async {
        guard let self, let item, generation == self.operationGeneration else { return }
        switch item.status {
        case .readyToPlay:
          self.preparedReady = true
          self.prepareStatusObservation?.invalidate()
          self.prepareStatusObservation = nil
          self.prepareTimeout?.cancel()
          self.prepareTimeout = nil
          self.finishPrepare(true)
        case .failed:
          self.clearPreparedNext(resolvePending: false)
          self.finishPrepare(false)
        case .unknown:
          break
        @unknown default:
          break
        }
      }
    }
    let timeout = DispatchWorkItem { [weak self] in
      guard let self, generation == self.operationGeneration else { return }
      self.clearPreparedNext(resolvePending: false)
      self.finishPrepare(false)
    }
    prepareTimeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
  }

  private func installActiveObservers(item: AVPlayerItem) {
    removeActiveObservers()
    activeTimeObserver = activePlayer.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      self.updateCrossfade()
      self.finishAtExpectedEndIfNeeded()
      self.publishState()
      self.updateNowPlayingInfo()
    }
    activeTimeControlObservation = activePlayer.observe(
      \.timeControlStatus,
      options: [.new]
    ) { [weak self] _, _ in
      DispatchQueue.main.async {
        self?.publishState(force: true)
        self?.updateNowPlayingInfo()
      }
    }
    activeItemStatusObservation = item.observe(\.status, options: [.new]) {
      [weak self, weak item] _, _ in
      DispatchQueue.main.async {
        guard let self, let item, item.status == .failed else { return }
        self.failActivePlayback(item.error?.localizedDescription)
      }
    }
    completionObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self, weak item] _ in
      guard let self, let item, self.activePlayer.currentItem === item else { return }
      self.handleActiveCompletion()
    }
  }

  private func removeActiveObservers() {
    if let activeTimeObserver {
      activePlayer.removeTimeObserver(activeTimeObserver)
    }
    activeTimeObserver = nil
    activeTimeControlObservation?.invalidate()
    activeTimeControlObservation = nil
    activeItemStatusObservation?.invalidate()
    activeItemStatusObservation = nil
    if let completionObserver {
      NotificationCenter.default.removeObserver(completionObserver)
      self.completionObserver = nil
    }
  }

  private func updateCrossfade() {
    guard playbackActive,
      requestedPlaying,
      preparedReady,
      preparedMetadata != nil,
      let duration = effectiveDuration(
        for: activePlayer,
        metadata: activeMetadata
      ),
      duration > 0
    else {
      activePlayer.volume = playbackVolume
      return
    }
    let position = max(0, finiteSeconds(activePlayer.currentTime()) ?? 0)
    let remaining = max(0, duration - position)
    guard remaining <= crossfadeDuration else {
      activePlayer.volume = playbackVolume
      return
    }

    let incomingFactor = min(1, max(0, 1 - remaining / crossfadeDuration))
    let outgoingFactor = min(1, max(0, remaining / crossfadeDuration))
    activePlayer.volume = playbackVolume * Float(outgoingFactor)
    standbyPlayer.volume = playbackVolume * Float(incomingFactor)
    if !crossfadeStarted {
      crossfadeStarted = true
      let elapsed = max(0, crossfadeDuration - remaining)
      standbyPlayer.seek(
        to: CMTime(seconds: elapsed, preferredTimescale: 600),
        toleranceBefore: .zero,
        toleranceAfter: .zero
      ) { [weak self] _ in
        guard let self, self.crossfadeStarted, self.requestedPlaying else { return }
        self.standbyPlayer.play()
        self.publishState(force: true)
      }
    } else if standbyPlayer.timeControlStatus != .playing {
      standbyPlayer.play()
    }
  }

  private func handleActiveCompletion() {
    guard !activeCompletionHandled else { return }
    activeCompletionHandled = true
    guard preparedReady, crossfadeStarted, preparedMetadata != nil else {
      requestedPlaying = false
      activePlayer.volume = playbackVolume
      publishState(force: true)
      updateNowPlayingInfo()
      channel.invokeMethod("completed", arguments: nil)
      return
    }
    promotePreparedPlayer()
  }

  private func promotePreparedPlayer() {
    guard let metadata = preparedMetadata, standbyPlayer.currentItem != nil else { return }
    let retiredPlayer = activePlayer
    removeActiveObservers()
    retiredPlayer.pause()
    retiredPlayer.volume = 0
    activeIndex = 1 - activeIndex
    activeMetadata = metadata
    hasPrevious = true
    hasNext = metadata.hasNext
    preparedMetadata = nil
    preparedReady = false
    crossfadeStarted = false
    activeCompletionHandled = false
    prepareStatusObservation?.invalidate()
    prepareStatusObservation = nil
    prepareTimeout?.cancel()
    prepareTimeout = nil
    activePlayer.volume = playbackVolume
    activePlayer.isMuted = false
    if let item = activePlayer.currentItem {
      installActiveObservers(item: item)
    }
    artwork = nil
    loadArtwork(from: activeMetadata.thumbnailUrl)
    activateRemoteCommands()
    publishState(force: true)
    updateNowPlayingInfo()
    channel.invokeMethod("advanced", arguments: nil)
  }

  private func play() {
    guard playbackActive else { return }
    configureAudioSession()
    remoteControlsEnabled = true
    activateRemoteCommands()
    requestedPlaying = true
    if isAtEnd(activePlayer) {
      activeCompletionHandled = false
      activePlayer.seek(to: .zero)
    }
    activePlayer.play()
    if crossfadeStarted {
      standbyPlayer.play()
    }
    publishState(force: true)
    updateNowPlayingInfo()
  }

  private func pause() {
    guard playbackActive else { return }
    requestedPlaying = false
    activePlayer.pause()
    standbyPlayer.pause()
    publishState(force: true)
    updateNowPlayingInfo()
  }

  private func seek(_ rawArguments: Any?) {
    guard playbackActive else { return }
    let arguments = rawArguments as? [String: Any]
    let requestedMilliseconds = millisecondsValue(arguments?["positionMilliseconds"])
    let expectedMilliseconds = activeMetadata.expectedDurationMilliseconds
    let milliseconds = expectedMilliseconds > 0
      ? min(max(0, requestedMilliseconds), expectedMilliseconds)
      : max(0, requestedMilliseconds)
    if expectedMilliseconds <= 0 || milliseconds < expectedMilliseconds - 50 {
      activeCompletionHandled = false
    }
    resetCrossfadeForSeek()
    activePlayer.seek(
      to: CMTime(value: milliseconds, timescale: 1000),
      toleranceBefore: .zero,
      toleranceAfter: .zero
    ) { [weak self] _ in
      self?.publishState(force: true)
      self?.updateNowPlayingInfo()
    }
  }

  private func setVolume(_ rawArguments: Any?) {
    let arguments = rawArguments as? [String: Any]
    playbackVolume = clampedVolume(arguments?["volume"] as? Double ?? 1)
    if crossfadeStarted {
      updateCrossfade()
    } else {
      activePlayer.volume = playbackVolume
      standbyPlayer.volume = 0
    }
  }

  private func updateNavigation(_ rawArguments: Any?) {
    let arguments = rawArguments as? [String: Any]
    hasPrevious = arguments?["hasPrevious"] as? Bool == true
    hasNext = arguments?["hasNext"] as? Bool == true
    if remoteControlsEnabled {
      activateRemoteCommands()
    }
  }

  private func resetCrossfadeForSeek() {
    guard crossfadeStarted else { return }
    standbyPlayer.pause()
    standbyPlayer.seek(to: .zero)
    standbyPlayer.volume = 0
    crossfadeStarted = false
    activePlayer.volume = playbackVolume
  }

  private func clearPreparedNext(resolvePending: Bool) {
    prepareStatusObservation?.invalidate()
    prepareStatusObservation = nil
    prepareTimeout?.cancel()
    prepareTimeout = nil
    standbyPlayer.pause()
    standbyPlayer.replaceCurrentItem(with: nil)
    standbyPlayer.volume = 0
    preparedMetadata = nil
    preparedReady = false
    crossfadeStarted = false
    activePlayer.volume = playbackVolume
    if resolvePending {
      finishPrepare(false)
    }
  }

  private func stop() {
    operationGeneration += 1
    finishOpen(false)
    clearPreparedNext(resolvePending: true)
    removeActiveObservers()
    for player in players {
      player.pause()
      player.replaceCurrentItem(with: nil)
      player.volume = 0
    }
    requestedPlaying = false
    resumeAfterInterruption = false
    playbackActive = false
    remoteControlsEnabled = true
    activeIndex = 0
    activeCompletionHandled = false
    artwork = nil
    deactivateRemoteCommands()
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    try? AVAudioSession.sharedInstance().setActive(
      false,
      options: .notifyOthersOnDeactivation
    )
    publishState(force: true)
  }

  private func configureAudioSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(
        .playback,
        mode: .default,
        options: [.allowBluetoothA2DP, .allowAirPlay]
      )
      try session.setActive(true)
    } catch {
      publishFailure(error.localizedDescription)
    }
  }

  @objc private func handleAudioRouteChange(_ notification: Notification) {
    guard playbackActive,
      let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
      let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
      reason == .oldDeviceUnavailable,
      let previousRoute = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey]
        as? AVAudioSessionRouteDescription,
      previousRoute.outputs.contains(where: isPrivateAudioOutput)
    else { return }
    pause()
    channel.invokeMethod("pausedByAudioRouteChange", arguments: nil)
  }

  @objc private func handleAudioInterruption(_ notification: Notification) {
    guard playbackActive,
      let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: typeValue)
    else { return }
    switch type {
    case .began:
      resumeAfterInterruption = requestedPlaying
      pause()
    case .ended:
      let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey]
        as? UInt ?? 0
      let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
      if resumeAfterInterruption && options.contains(.shouldResume) {
        play()
      }
      resumeAfterInterruption = false
    @unknown default:
      break
    }
  }

  private func isPrivateAudioOutput(_ output: AVAudioSessionPortDescription) -> Bool {
    switch output.portType {
    case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .carAudio, .headphones, .airPlay:
      return true
    default:
      return false
    }
  }

  private func activateRemoteCommands() {
    deactivateRemoteCommands()
    guard playbackActive else { return }
    let center = MPRemoteCommandCenter.shared()
    center.playCommand.isEnabled = true
    center.pauseCommand.isEnabled = true
    center.stopCommand.isEnabled = false
    center.previousTrackCommand.isEnabled = hasPrevious
    center.nextTrackCommand.isEnabled = hasNext
    center.changePlaybackPositionCommand.isEnabled = true
    center.skipForwardCommand.isEnabled = false
    center.skipBackwardCommand.isEnabled = false

    addTarget(center.playCommand) { [weak self] _ in
      self?.play()
      return .success
    }
    addTarget(center.pauseCommand) { [weak self] _ in
      self?.pause()
      return .success
    }
    if hasPrevious {
      addTarget(center.previousTrackCommand) { [weak self] _ in
        self?.channel.invokeMethod("previousRequested", arguments: nil)
        return .success
      }
    }
    if hasNext {
      addTarget(center.nextTrackCommand) { [weak self] _ in
        self?.channel.invokeMethod("nextRequested", arguments: nil)
        return .success
      }
    }
    addTarget(center.changePlaybackPositionCommand) { [weak self] event in
      guard let self,
        let event = event as? MPChangePlaybackPositionCommandEvent
      else { return .commandFailed }
      self.resetCrossfadeForSeek()
      let duration = self.effectiveDuration(
        for: self.activePlayer,
        metadata: self.activeMetadata
      )
      let nonnegativeTarget = max(0, event.positionTime)
      let target = duration.map { min(nonnegativeTarget, $0) } ?? nonnegativeTarget
      if duration == nil || target < (duration ?? 0) - 0.05 {
        self.activeCompletionHandled = false
      }
      self.activePlayer.seek(
        to: CMTime(seconds: target, preferredTimescale: 600)
      )
      self.publishState(force: true)
      self.updateNowPlayingInfo()
      return .success
    }
  }

  private func addTarget(
    _ command: MPRemoteCommand,
    handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
  ) {
    let target = command.addTarget(handler: handler)
    remoteCommandTargets.append((command, target))
  }

  private func deactivateRemoteCommands() {
    for (command, target) in remoteCommandTargets {
      command.removeTarget(target)
    }
    remoteCommandTargets.removeAll()
  }

  private func publishState(force: Bool = false) {
    let now = Date()
    if !force && now.timeIntervalSince(lastStatePublishTime) < 0.2 {
      return
    }
    lastStatePublishTime = now
    let item = activePlayer.currentItem
    let activePlaying = activePlayer.timeControlStatus == .playing
    let incomingPlaying = crossfadeStarted
      && standbyPlayer.timeControlStatus == .playing
    let buffering = playbackActive && (
      activePlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate
        || item?.isPlaybackBufferEmpty == true
    )
    channel.invokeMethod(
      "stateChanged",
      arguments: [
        "positionMilliseconds": safeMilliseconds(activePlayer.currentTime()),
        "durationMilliseconds": effectiveDurationMilliseconds(
          for: activePlayer,
          metadata: activeMetadata
        ),
        "playing": activePlaying || incomingPlaying,
        "buffering": buffering,
      ]
    )
  }

  private func updateNowPlayingInfo() {
    guard playbackActive else { return }
    let rate = requestedPlaying ? 1.0 : 0.0
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: activeMetadata.title,
      MPMediaItemPropertyArtist: activeMetadata.artist,
      MPNowPlayingInfoPropertyElapsedPlaybackTime:
        finiteSeconds(activePlayer.currentTime()) ?? 0,
      MPNowPlayingInfoPropertyPlaybackRate: rate,
    ]
    if let duration = effectiveDuration(
      for: activePlayer,
      metadata: activeMetadata
    ) {
      info[MPMediaItemPropertyPlaybackDuration] = duration
    }
    if let artwork {
      info[MPMediaItemPropertyArtwork] = artwork
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  private func loadArtwork(from urlString: String) {
    artworkRequest += 1
    let request = artworkRequest
    guard let url = URL(string: urlString), !urlString.isEmpty else { return }
    URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
      guard let self, request == self.artworkRequest,
        let data, let image = UIImage(data: data)
      else { return }
      DispatchQueue.main.async {
        guard request == self.artworkRequest else { return }
        self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        self.updateNowPlayingInfo()
      }
    }.resume()
  }

  private func metadata(from arguments: [String: Any]) -> IosNativeAudioMetadata {
    IosNativeAudioMetadata(
      title: arguments["title"] as? String ?? "",
      artist: arguments["artist"] as? String ?? "",
      thumbnailUrl: arguments["thumbnailUrl"] as? String ?? "",
      hasNext: arguments["hasNext"] as? Bool == true,
      expectedDurationMilliseconds: millisecondsValue(
        arguments["expectedDurationMilliseconds"]
      )
    )
  }

  private func finishOpen(_ value: Bool) {
    openStatusObservation?.invalidate()
    openStatusObservation = nil
    openTimeout?.cancel()
    openTimeout = nil
    guard let pendingOpenResult else { return }
    self.pendingOpenResult = nil
    pendingOpenResult(value)
  }

  private func finishPrepare(_ value: Bool) {
    guard let pendingPrepareResult else { return }
    self.pendingPrepareResult = nil
    pendingPrepareResult(value)
  }

  private func failActivePlayback(_ description: String?) {
    requestedPlaying = false
    activePlayer.pause()
    standbyPlayer.pause()
    publishState(force: true)
    publishFailure(description ?? "The native iOS audio stream failed.")
  }

  private func publishFailure(_ message: String) {
    channel.invokeMethod("failed", arguments: message)
  }

  private func clampedVolume(_ value: Double) -> Float {
    Float(min(1, max(0, value)))
  }

  private func millisecondsValue(_ value: Any?) -> Int64 {
    if let value = value as? Int64 { return value }
    if let value = value as? Int { return Int64(value) }
    if let value = value as? NSNumber { return value.int64Value }
    return 0
  }

  private func finiteSeconds(_ time: CMTime?) -> Double? {
    guard let seconds = time?.seconds, seconds.isFinite else { return nil }
    return seconds
  }

  private func safeMilliseconds(_ time: CMTime?) -> Int64 {
    guard let seconds = finiteSeconds(time) else { return 0 }
    return Int64(max(0, seconds * 1000))
  }

  private func applyExpectedEndTime(
    to item: AVPlayerItem,
    metadata: IosNativeAudioMetadata
  ) {
    guard metadata.expectedDurationMilliseconds > 0 else { return }
    item.forwardPlaybackEndTime = CMTime(
      value: metadata.expectedDurationMilliseconds,
      timescale: 1000
    )
  }

  private func effectiveDuration(
    for player: AVPlayer,
    metadata: IosNativeAudioMetadata
  ) -> Double? {
    if metadata.expectedDurationMilliseconds > 0 {
      return Double(metadata.expectedDurationMilliseconds) / 1000.0
    }
    return finiteSeconds(player.currentItem?.duration)
  }

  private func effectiveDurationMilliseconds(
    for player: AVPlayer,
    metadata: IosNativeAudioMetadata
  ) -> Int64 {
    if metadata.expectedDurationMilliseconds > 0 {
      return metadata.expectedDurationMilliseconds
    }
    return safeMilliseconds(player.currentItem?.duration)
  }

  private func finishAtExpectedEndIfNeeded() {
    let expectedMilliseconds = activeMetadata.expectedDurationMilliseconds
    guard expectedMilliseconds > 0,
      safeMilliseconds(activePlayer.currentTime()) >= expectedMilliseconds - 50
    else { return }
    handleActiveCompletion()
  }

  private func isAtEnd(_ player: AVPlayer) -> Bool {
    guard let duration = effectiveDuration(
      for: player,
      metadata: activeMetadata
    ), duration > 0,
      let position = finiteSeconds(player.currentTime())
    else { return false }
    return position >= duration - 0.05
  }
}
