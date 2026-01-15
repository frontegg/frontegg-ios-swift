# Project setup

This section walks you through configuring the Frontegg Swift SDK, including setting up your project, integrating with SwiftUI or UIKit, and registering your associated domain for secure auth flows.

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

## Register your domain with Frontegg

To enable domain-based features, you must register your associated domain with Frontegg for each environment. To do this:

1. Generate an environment token as desxcribed in [this guide](https://docs.frontegg.com/reference/getting-started-with-your-api).

2. Send a `POST` request to the following endpoint: `POST https://api.frontegg.com/vendors/resources/associated-domains/v1/ios`. Example payload:

```json
{
  "appId": "{{ASSOCIATED_DOMAIN}}"
}
```

Replace `{{ASSOCIATED_DOMAIN}}` with the domain you want to use (e.g., `example.com`).


3. Configure associated domains in Xcode:

- Open your project in **Xcode**.
- In the **Project Navigator**, click on your **project name**.
- Select your **target application**.
- Go to the **Signing & Capabilities** tab.
- Click **+ Capability**, then add **Associated Domains**.
- Under the **Associated Domains** section, click the **+** button.
- Add the following entries:

   ```
   applinks:your-associated-domain.com
   webcredentials:your-associated-domain.com
   ```

  For example, if your domain is `https://example.com`, add `applinks:example.com` and `webcredentials:example.com`.

- Click **Done**.