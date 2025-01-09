//
//  StreamViewController.swift
//  demo-uikit
//
//  Created by David Antoon on 08/01/2025.
//

import Foundation
import UIKit
import Combine
import FronteggSwift


class StreamViewController: BaseViewController, UITextFieldDelegate {
    var isSplitView: Bool = false
    var isPortrait : Bool = true
    var isLiveStreamOn : Bool = false
    
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var zoominLogoImg: UIImageView!
    @IBOutlet weak var mainView:       UIView!
    @IBOutlet weak var streamBgView:       UIView!
    @IBOutlet weak var optionView:       UIView!
    @IBOutlet weak var lblChannelName: UILabel!
    @IBOutlet weak var btnScreenToggle:       UIButton!
    @IBOutlet weak var videoPlayerHeight: NSLayoutConstraint!
    
    @IBOutlet weak var testLabel: UILabel!
    @IBOutlet weak var loadingLabel: UILabel!
    @IBOutlet weak var refreshingTokenLabel: UILabel!
    
    
    @IBOutlet weak var videoPlayerTrailingConstraint: NSLayoutConstraint!
    @IBOutlet weak var optionViewTopConstraint: NSLayoutConstraint!
    @IBOutlet weak var optionViewLeadingConstraint: NSLayoutConstraint!
    @IBOutlet weak var verticalForStreamConstraint: NSLayoutConstraint!
    @IBOutlet weak var streamTopConstraint: NSLayoutConstraint!
    @IBOutlet weak var streamBottomConstraint: NSLayoutConstraint!

    
    private var cancellable :AnyCancellable? = nil
    private var _isStarting: Bool = false
    private var isShowing: Bool = false
    
    @IBOutlet weak var vMainBg: UIView!
    @IBOutlet weak var vDescriptionBg: UIView!
    @IBOutlet weak var vRoom: UIView!
    @IBOutlet weak var btnRoomDropDown: UIButton!
    @IBOutlet weak var btnStart: UIButton!
    @IBOutlet weak var descTextField: UITextField!
    @IBOutlet weak var vLiveStreamRoomSelection: UIView!
    private static let DEFAULT_TIMEOUT = 0
    var main_vc : MainViewController! = nil
    @IBOutlet weak var btnStopLiveStream: UIButton!
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()

        
        //let menuSize = LayUtil.getRealSize(100)
        self.setVideoPlayerHeight()
        self.setupAppFlow()
        
        if (appDelegate.fronteggAuth.isLoading) { ///Checking if frontegg token is loading. If its true then wait for change its value false.
            
            testLabel.text = "Loading..."
            cancellable = appDelegate.fronteggAuth.$isLoading
                .sink { [weak self] newValue in
                    guard let self = self else { return }
                    print("Viewdidload loading status: ******** \(newValue)")
                    if !(newValue) {
                        self.cancellable?.cancel()
                        
                        ///This is API call for get user profile
                        self.getUserProfile { success in
                            if(success){
                                self.setupUI()
                            }else {
                                self.testLabel.text = "No Access Token"
                            }
                        }
                    }
                }
        } else { /// if frontegg token is not loading then simply call API
            
            ///This is API call for get user profile
            self.getUserProfile { success in
                if(success){
                    self.setupUI()
                }else {
                    self.testLabel.text = "No Access Token"
                }
            }
        }
    }
    
    
    
    
    func setupUI(){
        
        if appDelegate.fronteggAuth.isLoading {
            self.loadingLabel.text = "Loading..."
        } else {
            self.loadingLabel.text = "App Ready"
        }
        
        if appDelegate.fronteggAuth.refreshingToken {
            self.refreshingTokenLabel.text = "Refreshing Token..."
        } else {
            self.refreshingTokenLabel.text = "Token Ready"
        }
        
        
        if appDelegate.fronteggAuth.isAuthenticated {
            getUserProfile { success in
                if success {
                    let accessToken = String(appDelegate.fronteggAuth.accessToken!.suffix(40))
                    self.testLabel.text = "Access Token Valid \n\n\(accessToken)"
                } else {
                    self.testLabel.text = "No Access"
                }
            }
        }else {
            self.testLabel.text = "No Access"
        }
        
        
        
        
    }
    
    
    /// Calculates the optimal delay for refreshing the token based on the expiration time.
    /// - Parameter expirationTime: The expiration time of the token in seconds since the Unix epoch.
    /// - Returns: The calculated offset in seconds before the token should be refreshed. If the remaining time is less than 20 seconds, it returns 0 for immediate refresh.
    func calculateOffset(expirationTime: Int) -> TimeInterval {
        let now = Date().timeIntervalSince1970 * 1000 // Current time in milliseconds
        let remainingTime = (Double(expirationTime) * 1000) - now
        
        let minRefreshWindow: Double = 20000 // Minimum 20 seconds before expiration, in milliseconds
        let adaptiveRefreshTime = remainingTime * 0.8 // 80% of remaining time
        
        return remainingTime > minRefreshWindow ? adaptiveRefreshTime / 1000 : max((remainingTime - minRefreshWindow) / 1000, 0)
    }
    
    func getUserProfile(completion: (Bool) -> Void) {
        
        do{
            guard let accessToken = self.appDelegate.fronteggAuth.accessToken else { 
                
                print("No access token")
                completion(false)
                return
            }
            print("Access token found. Attempting to decode JWT...")
            
            // Decode the access token to get the expiration time
            let decode = try JWTHelper.decode(jwtToken: accessToken)
            let expirationTime = decode["exp"] as! Int
            print("JWT decoded successfully. Expiration time: \(expirationTime)")
            
            let offset = calculateOffset(expirationTime: expirationTime)
            print("Calculated offset for token refresh: \(offset) seconds")
            
            completion(offset > 0)
        } catch {
            print("Error access token \(error.localizedDescription)")
            completion(false)
        }
        
        
        
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
      return .all
    }

    private var windowInterface : UIInterfaceOrientation? {
            return self.view.window?.windowScene?.interfaceOrientation
    }
    
    func setVideoPlayerHeight(){
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            
        }
    }
    @objc func orientationDidChange(){
        self.view.endEditing(true)
        guard let windowInterface = self.windowInterface else { return }
        
        isSplitView = false
        // call function only if UI is not in intended orientation
        if windowInterface.isPortrait ==  true && isPortrait == false{
            self.setPortraitView()
        } else if windowInterface.isPortrait  == false && isPortrait == true{
            self.setLandscapeView()
        }
    
    }
    override func willTransition(to newCollection: UITraitCollection, with coordinator: UIViewControllerTransitionCoordinator) {
        super.willTransition(to: newCollection, with: coordinator)
       // if UIDevice.current.userInterfaceIdiom == .phone{
            self.orientationDidChange()
//        }
    }
    
    func setPortraitView(){
        
        scrollView.setZoomScale(1, animated: false)
        if UIDevice.current.userInterfaceIdiom == .pad{
            self.videoPlayerTrailingConstraint.constant = 0
            self.optionViewTopConstraint.constant = 0
            self.optionViewLeadingConstraint.constant = 0
        }
        self.setVideoPlayerHeight()
        self.optionView.isHidden = false
        self.lblChannelName.isHidden = false
        self.zoominLogoImg.isHidden = false
    
        self.btnScreenToggle.setImage(UIImage(named:"full_screen"), for: .normal)
        self.setPlayerFrame(islandscape : false)
        isPortrait = true
    }
    
    func setLandscapeView(){
        scrollView.setZoomScale(1, animated: false)
        
        self.videoPlayerHeight.constant = self.view.layer.bounds.width
        self.videoPlayerTrailingConstraint.constant = 0
        optionView.isHidden = true
        if UIDevice.current.userInterfaceIdiom == .phone{
            lblChannelName.isHidden = true
            zoominLogoImg.isHidden = true
        }
        else{
            self.centerStreamViewInLandscapeMode()
        }
        self.btnScreenToggle.setImage(UIImage(named: "small_screen"), for: .normal)
        self.setPlayerFrame(islandscape : true)
        isPortrait = false
    }

    func setPlayerFrame(islandscape: Bool){
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
            self.verticalForStreamConstraint.constant = islandscape ? 0 : 10
        
            self.view.bringSubviewToFront(self.mainView)
           
        })
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
         
        isShowing = true
        // Do any additional setup after loading the view.
    }
    
   
    func addObservers(){
         NotificationCenter.default.addObserver(self,
                                             selector: #selector(orientationDidChange),
                           name: UIDevice.orientationDidChangeNotification, object: nil)

       
    }
    
    
    private var subscriptions =  Set<AnyCancellable>()
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        
        
        subscriptions.insert(appDelegate.fronteggAuth.$accessToken
            .sink { accessToken in
                if let token = accessToken {
                    self.testLabel.text = "Valid token \n\n\(String(token.suffix(40)))"
                } else {
                    if(self.appDelegate.fronteggAuth.showLoader) {
                        self.testLabel.text = "Loading..."
                    }else {
                        self.testLabel.text = "No token"
                    }
                }
            })
        
        
        subscriptions.insert(appDelegate.fronteggAuth.$isLoading
            .sink { isLoading in
                if isLoading {
                    self.loadingLabel.text = "Loading..."
                } else {
                    self.loadingLabel.text = "App Ready"
                }
            })
        
        subscriptions.insert(appDelegate.fronteggAuth.$refreshingToken
            .sink { refreshingToken in
                if refreshingToken {
                    self.refreshingTokenLabel.text = "Refreshing Token..."
                } else {
                    self.refreshingTokenLabel.text = "Token Ready"
                }
            })
        
        
        self.setupUI()
        
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        isShowing = false
        NotificationCenter.default.removeObserver(self)
        
        self.subscriptions.forEach { cancelable in
            cancelable.cancel()
        }
        
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @IBAction func didTapFullScreenButton(_ sender: Any) {
      
        guard let windowInterface = self.windowInterface else { return }
        
        if windowInterface.isLandscape ==  true  &&  UIDevice.current.userInterfaceIdiom == .pad{
            if isSplitView{
                self.setOrResetSplitView(reset: true)
            }
            else{
                self.setOrResetSplitView(reset: false)
            }
        }
        else if #available(iOS 16.0, *) {
                guard let windowSceen = self.view.window?.windowScene else { return }
                if windowSceen.interfaceOrientation == .portrait {
                    windowSceen.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { error in
                        print(error.localizedDescription)
                   }
                    if UIDevice.current.userInterfaceIdiom == .pad{
                        self.setLandscapeView()
                    }
                } else {
                    windowSceen.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { error in
                        print(error.localizedDescription)
                    }
                    if UIDevice.current.userInterfaceIdiom == .pad{
                        self.setPortraitView()
                    }
                }
            } else {
                if UIDevice.current.orientation == .portrait {
                    let orientation = UIInterfaceOrientation.landscapeRight.rawValue
                    UIDevice.current.setValue(orientation, forKey: "orientation")
                    if UIDevice.current.userInterfaceIdiom == .pad{
                        self.setLandscapeView()
                    }
                } else {
                    let orientation = UIInterfaceOrientation.portrait.rawValue
                    UIDevice.current.setValue(orientation, forKey: "orientation")
                    if UIDevice.current.userInterfaceIdiom == .pad{
                        self.setPortraitView()
                    }
                }
            }
        //}
        
    }
    
    func centerStreamViewInLandscapeMode(){
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: {
            //self.streamViewTopConstraints.constant = (self.videoPlayerHeight.constant/2 - (self.scrollView.frame.height/2))
        })
    }
    func setOrResetSplitView(reset: Bool){
        self.btnScreenToggle.setImage(UIImage(named: reset ? "small_screen" : "full_screen"), for: .normal)
        self.isSplitView = reset ? false : true
        self.videoPlayerTrailingConstraint.constant = reset ? 0 : self.view.frame.width * 0.3
        self.centerStreamViewInLandscapeMode()
      
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
          
            //self.streamViewTopConstraints.constant = (self.videoPlayerHeight.constant/2 - (self.scrollView.frame.height))+23
            self.optionViewTopConstraint.constant = reset ? 0 : -self.streamBgView.frame.height
            self.optionViewLeadingConstraint.constant = reset ? 0 : self.streamBgView.frame.width
            self.optionView.isHidden = reset ?  true : false
            self.setPlayerFrame(islandscape:  true)
        })
       
    }
    
    
    @IBAction func logoutButton (){
        appDelegate.fronteggAuth.logout() { _ in

            Constants.resetToLogin()
        }
  }
    
    
    @objc func onActiveApp() {
        if(isLiveStreamOn == false){
            isShowing = true
            addObservers()
            print("**** App on Active called *****")
            
            if (appDelegate.fronteggAuth.isLoading) { ///Checking if frontegg token is loading. If its true then wait for change its value false.
                cancellable = appDelegate.fronteggAuth.$isLoading
                    .sink { [weak self] newValue in
                        guard let self = self else { return }
                        print("on active loading status: ******** \(newValue)")
                        if !(newValue) {
                            self.cancellable?.cancel()
                            DispatchQueue.main.asyncAfter(deadline: .now()+0.1, execute: {
                                ///API call for load streams on dashboard
//                                self.loadOnlineStreams()
                            })
                        }
                    }
            } else { /// if frontegg token is not loading then call the load stream API
                DispatchQueue.main.asyncAfter(deadline: .now()+0.1, execute: { [weak self] in
                    guard let self = self else { return }
                    ///API call for load streams on dashboard
                    //self.loadOnlineStreams()
                })
            }
            
        }
    }
    @objc func onDeactiveApp() {
      //  print("App is in Backround")
        if(isLiveStreamOn == false){
            NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
            isShowing = false
        }
    }

    
    @IBAction func didTapGoliveSelectionBackground(_ sender: Any) {
        self.view.endEditing(true)
        self.vLiveStreamRoomSelection.isHidden = true
    }
    
    func fillRoomDropDownForLiveStream(){
        
    }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
    
    
    @IBAction func didTapRoomDropDown(_ sender: Any) {
        self.fillRoomDropDownForLiveStream()
    }
   
   @objc func checkForLiveStreamToLoad(){
    }
    
    
    private func keepScreen(on: Bool) {
        print("keepScreenOn: \(on)")
//        streamingPlayer.playerVC.player?.preventsDisplaySleepDuringVideoPlayback = !on
        UIApplication.shared.isIdleTimerDisabled = on
    }
    
}


extension StreamViewController{
    
    func setupAppFlow(){
        DispatchQueue.main.async {
            
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            self.main_vc = storyboard.instantiateViewController(withIdentifier: "MainViewController") as? MainViewController
            self.main_vc.parentVC = self
            self.children.forEach { child in
                child.willMove(toParent: nil)
                child.view.removeFromSuperview()
                child.removeFromParent()
            }
            
            
            self.addChild(self.main_vc)
        }
    }
}
    
