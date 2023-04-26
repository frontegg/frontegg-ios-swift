export default async function modifyEntitlements({github, context, fetch}) {
  const {writeFileSync} = await import("fs");
  await new Promise(resolve => {
    const intervalRef = setInterval(async () => {
      const response = await fetch('http://localhost:4001/ngrok');
      const body = await response.text();
      if (body.startsWith("https://")) {
        clearInterval(intervalRef)
        resolve(body);

        console.log('ngrok YRL',body)
        writeFileSync(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>com.apple.developer.associated-domains</key>
\t<array>
\t\t<string>applinks:d645-109-65-152-21.ngrok-free.app</string>
\t</array>
</dict>
</plist>
`, `${github.workspace}/demo/demo/demo.entitlements`, {encoding: 'utf8'});
      }
    }, 500);
  })
}
