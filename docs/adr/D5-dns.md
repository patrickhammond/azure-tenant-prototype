# D5 · DNS

**Status:** Accepted · **Group:** The application

## Required

Every internal application is reached under **`example.com`**. Nobody sees an
`*.azurecontainerapps.io` URL.

| Environment | Pattern | Example |
| ----------- | ------- | ------- |
| Production  | `<app>.example.com` | `lime.example.com` |
| Development | `<app>.dev.example.com` | `lime.dev.example.com` |

Container Apps **custom domains with managed certificates**, created **during** provisioning rather
than afterwards.

## Why

A platform-generated hostname is unmemorable, looks like a phishing link pasted into a chat channel,
and couples the address to the platform.
