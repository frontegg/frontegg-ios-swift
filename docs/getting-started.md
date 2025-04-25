# Getting started with Frontegg Swift SDK

Welcome to the Frontegg Swift SDK! Easily integrate Frontegg’s out-of-the-box authentication and user management functionalities into your iOS applications for a seamless and secure user experience.

The Frontegg Swift SDK can be used in two ways:

1. With the hosted Frontegg login that will be called through a webview, enabling all login methods supported on the login box
2. By directly using Frontegg APIs from your custom UI, with available methods

The Frontegg Swift SDK automatically handles token refresh behind the scenes, ensuring your users maintain authenticated sessions without manual intervention.

## Supported languages and platform
The minimum supported Swift version is 5.3.
iOS 14+ is required for this integration

## Prepare your Frontegg environment

- Navigate to Frontegg Portal [ENVIRONMENT] → `Keys & domains`
- Copy your Frontegg domain from the Frontegg domain section.
- Navigate to [ENVIRONMENT] → Authentication → Login method
- Make sure hosted login is toggled on.
- Add the following redirect URLs:

  ```
  {{IOS_BUNDLE_IDENTIFIER}}://{{FRONTEGG_BASE_URL}}/ios/oauth/callback
  {{FRONTEGG_BASE_URL}}/oauth/authorize
  ```

- Replace `{{IOS_BUNDLE_IDENTIFIER}}` with your IOS bundle identifier.
- Replace `{{FRONTEGG_BASE_URL}}` with your Frontegg domain, i.e `app-xxxx.frontegg.com` or your custom domain.


## Add the Frontegg Swift package

- Open Xcode.
- Go to **File > Add Packages**.
- Enter `https://github.com/frontegg/frontegg-ios-swift`.
- Click **Add Package**.

## Create Frontegg.plist

1. Add a new file named `Frontegg.plist` to your root project directory.
2. Add the following content:

  ```xml
  <plist version="1.0">
    <dict>
      <key>baseUrl</key>
      <string>https://{{FRONTEGG_BASE_URL}}</string>
      <key>clientId</key>
      <string>{{FRONTEGG_CLIENT_ID}}</string>
    </dict>
  </plist>
  ```

- Replace `{{FRONTEGG_BASE_URL}}` with your Frontegg domain, i.e `app-xxxx.frontegg.com`
- Replace `{{FRONTEGG_CLIENT_ID}}` with your Frontegg client ID.

## SwiftUI integration

1. Open your `App` struct and wrap your root view with `FronteggWrapper`.

```swift
import SwiftUI
import FronteggSwift

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            FronteggWrapper {
                MyApp()
            }
        }
    }
}
```

2. Create a new SwiftUI view called `MyApp` (or use your existing main view). This view will handle whether the user is logged in.
3. In your `MyApp` view, use the `@EnvironmentObject` to access Frontegg's authentication state:

```swift
struct MyApp: View {
    @EnvironmentObject var fronteggAuth: FronteggAuth

    var body: some View {
        ZStack {
            if fronteggAuth.isAuthenticated {
                // Replace with your app's main content
                MainAppView()
            } else {
                // Display login button
                Button(action: {
                    fronteggAuth.login()
                }) {
                    Text("Login")
                }
            }
        }
    }
}
```

4. If you want to show a custom loading screen (e.g. splash screen) while authentication is initializing, create a `LoaderView` and pass it to `FronteggWrapper`:

```swift
FronteggWrapper(loaderView: AnyView(LoaderView())) {
    MyApp()
}
```


## UIKit integration

1. Open your `AppDelegate.swift` and initialize the Frontegg SDK during app launch:

```swift
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        FronteggApp.shared.didFinishLaunchingWithOptions()
        return true
    }
```

2. Create `AuthenticationController` class that extends `AbstractFronteggController` from `FronteggSwift`:

```swift
import UIKit
import FronteggSwift

class AuthenticationController: AbstractFronteggController {

    override func navigateToAuthenticated() {
        // Navigate to your authenticated screen
        let mainStoryboard = UIStoryboard(name: "Main", bundle: nil)

        // Set this Storyboard ID in Interface Builder
        let viewController = mainStoryboard.instantiateViewController(withIdentifier: "authenticatedScreen")
        self.view.window?.rootViewController = viewController
        self.view.window?.makeKeyAndVisible()
    }
}
```

3. In `Main.storyboard`:

* Add a new `UIViewController`.
* Set its Class to `AuthenticationController`.
* Set its Storyboard ID to `fronteggController`.
* Mark it as the `Initial View Controller`.

![AuthenticationController](./images/Authentication_controller.png)

4. Update `SceneDelegate.swift` to handle OAuth callback URLs:

```swift
func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    if let url = URLContexts.first?.url,
       url.startAccessingSecurityScopedResource() {
        defer { url.stopAccessingSecurityScopedResource() }

        if url.absoluteString.hasPrefix(FronteggApp.shared.baseUrl),
           FronteggApp.shared.auth.handleOpenUrl(url) {
            window?.rootViewController = AuthenticationController()
            window?.makeKeyAndVisible()
        }
    }
}

func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    if let url = userActivity.webpageURL,
       FronteggApp.shared.auth.handleOpenUrl(url) {
        window?.rootViewController = AuthenticationController()
        window?.makeKeyAndVisible()
    }
}
```

5. Access authenticated user in your `ViewController`:

```swift
import UIKit
import SwiftUI
import FronteggSwift
import Combine

class ExampleViewController: UIViewController {

    @IBOutlet weak var label: UILabel!
    var showLoader: Bool = true

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let fronteggAuth = FronteggApp.shared.auth
        label.text = fronteggAuth.user?.email ?? "Unknown"
    }

    @IBAction func logoutButton() {
        FronteggApp.shared.auth.logout() { _ in
            self.view.window?.rootViewController = AuthenticationController()
            self.view.window?.makeKeyAndVisible()
        }
    }
}
```

