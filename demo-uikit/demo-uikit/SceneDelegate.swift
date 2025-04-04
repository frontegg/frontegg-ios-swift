//
//  SceneDelegate.swift
//  demo-uikit
//
//  Created by David Antoon on 29/01/2024.
//

import UIKit
import FronteggSwift

/// A scene delegate for the demo application.
/// This component handles the scene delegate for the demo application.
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    
    let fronteggAuth = FronteggAuth.shared
    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).
        //        guard let _ = (scene as? UIWindowScene) else { return }
        //        
        
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            let initialVC: UIViewController
            
            if fronteggAuth.isAuthenticated {
                /// If the user is authenticated, the initial view controller is the stream view controller.
                initialVC = storyboard.instantiateViewController(withIdentifier: "StreamViewController")
            } else {
                /// If the user is not authenticated, the initial view controller is the login view controller.
                initialVC = storyboard.instantiateViewController(withIdentifier: "LoginViewController")
            }
            
            window.rootViewController = UINavigationController(rootViewController: initialVC)
            self.window = window
            window.makeKeyAndVisible()
        }
    }
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if let url = URLContexts.first?.url,
           url.startAccessingSecurityScopedResource() {
            defer  {
                url.stopAccessingSecurityScopedResource()
            }
            if url.absoluteString.hasPrefix( FronteggApp.shared.baseUrl ) {
                if(FronteggApp.shared.auth.handleOpenUrl(url)){
                    // Display your own Authentication View Controller
                    // to handle after oauth callback
                    window?.rootViewController = AuthenticationController()
                    window?.makeKeyAndVisible()
                    return
                }
            }
            
        }
    }
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        if let url = userActivity.webpageURL {
            if(FronteggApp.shared.auth.handleOpenUrl(url)){
                // Display your own Authentication View Controller
                // to handle after oauth callback
                window?.rootViewController = AuthenticationController()
                window?.makeKeyAndVisible()
                return
            }
        }
    }
    
    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }
    
    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    }
    
    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }
    
    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }
    
    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
    }
    
    
}

