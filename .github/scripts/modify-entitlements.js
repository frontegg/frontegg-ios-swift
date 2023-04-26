module.exports = async ({github, fetch, fs}) => {
  const {writeFileSync} = require('fs')
  const path = require('path')
  await new Promise(resolve => {
    const intervalRef = setInterval(async () => {
      const response = await fetch('http://localhost:4001/ngrok');
      const body = await response.text();
      if (body.startsWith("https://")) {
        clearInterval(intervalRef)

        console.log('ngrok URL', body)

          const host = (new URL("https://d645-109-65-152-21.ngrok-free.app")).host
        writeFileSync(path.join(__dirname, `../../demo/demo/demo.entitlements`),
          `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>com.apple.developer.associated-domains</key>
\t<array>
\t\t<string>applinks:${host}</string>
\t</array>
</dict>
</plist>
` , {encoding: 'utf8'});

        resolve();
      }
    }, 2000);
  })
}
