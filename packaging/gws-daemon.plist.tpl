<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>__LABEL__</string>

    <key>ProgramArguments</key>
    <array>
        <string>__UVX_BIN__</string>
        <string>workspace-mcp</string>
        <string>--single-user</string>
        <string>--tool-tier</string>
        <string>complete</string>
        <string>--transport</string>
        <string>streamable-http</string>
    </array>

    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>__HOME__</string>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>GOOGLE_OAUTH_CLIENT_ID</key>
        <string>__CLIENT_ID__</string>
        <key>GOOGLE_OAUTH_CLIENT_SECRET</key>
        <string>__CLIENT_SECRET__</string>
        <key>GOOGLE_MCP_CREDENTIALS_DIR</key>
        <string>__CREDS_DIR__</string>
        <key>WORKSPACE_MCP_PORT</key>
        <string>__PORT__</string>
        <key>OAUTHLIB_INSECURE_TRANSPORT</key>
        <string>1</string>
    </dict>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
        <key>Crashed</key>
        <true/>
    </dict>

    <key>ThrottleInterval</key>
    <integer>10</integer>

    <key>ExitTimeOut</key>
    <integer>30</integer>

    <key>ProcessType</key>
    <string>Background</string>

    <key>LimitLoadToSessionType</key>
    <array>
        <string>Aqua</string>
    </array>

    <key>StandardOutPath</key>
    <string>__LOG_DIR__/stdout.log</string>

    <key>StandardErrorPath</key>
    <string>__LOG_DIR__/stderr.log</string>

    <key>SoftResourceLimits</key>
    <dict>
        <key>NumberOfFiles</key>
        <integer>4096</integer>
    </dict>
</dict>
</plist>
