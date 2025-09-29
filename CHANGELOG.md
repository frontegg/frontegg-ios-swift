## v1.2.48
FR-22185 - Added support for trigger login with custom sso via WebAuthenticationSession
FR-22185 - Fix offline mode
FR-22001 - Support embedded social login flows
- Detect legacy social login flow when authorizationUrl starts with /identity/resources/auth/v2/user/sso/default/
- Add legacyAuthorizeURL method to generate legacy URLs
- Modify handleSocialLogin to automatically switch to legacy flow when needed
- Maintain backward compatibility with existing configurations

<!-- CURSOR_SUMMARY -->
---

> [!NOTE]
> Prepare v1.2.48 with changelog updates (custom SSO via WebAuthenticationSession, offline fix, embedded social login legacy flow) and bump podspec to 1.2.48.
> 
> - **Release prep: v1.2.48**
>   - **Changelog (`CHANGELOG.md`)**: add notes for custom SSO via `WebAuthenticationSession`, offline mode fix, and embedded social login legacy-flow detection/auto-switch (`legacyAuthorizeURL`, `handleSocialLogin`).
>   - **Archive**: move prior notes to `CHANGELOG.old.md` (adds `v1.2.47`).
>   - **Versioning**: bump `FronteggSwift.podspec` from `1.2.47` to `1.2.48`.
> 
> <sup>Written by [Cursor Bugbot](https://cursor.com/dashboard?tab=bugbot) for commit fbf469fe2f4dce0d80f654aa153033777082ab54. This will update automatically on new commits. Configure [here](https://cursor.com/dashboard?tab=bugbot).</sup>
<!-- /CURSOR_SUMMARY -->

## v1.2.47
This PR introduces fixes and enhancements to the logout flow, adds offline mode support, and addresses critical issues in login handling.
- updated readme with new frontegg.plist keys

## v1.2.46
- Modified `generateRedirectUri` method. It includes `path` now.
- Modified `AuthorizeUrlGenerator.generate` method.  It includes `path` now.
- Check Internet connection before run DEBUG checks

## v1.2.45
- Reduce number of full page load when loading login page

## v1.2.44
- Fix ConfigurationCheck.swift
- Updated example projects UI
Fix e2e trigger ref
- Added background color to web view to avoid blinks on redirect 

## v1.2.43
- Fix publish workflow

## v1.2.42
### 🔧 Enhancements
- **Improved WKWebView Performance**  
  Optimized the WebView initialization and loading flow for faster render and smoother UX.

- **Unified Loading Indicators**  
  Standardized the loading experience across login pages and social login flows for consistent UI behavior.

- **Social Login Stability**  
  Prevented unnecessary reloads of the login page when canceling a social login popup.

- **Unified Loader Support**  
  Integrated support for a centralized loading mechanism across the SDK.

---

### 🐞 Bug Fixes
- Fixed various crash scenarios related to view lifecycle and state handling in authentication flows.

---

### 🧪 QA & Automation
- **Simulator E2E Tests Added**  
  Extended test coverage with end-to-end tests running on iOS simulators.

- **Pre-Release E2E Trigger**  
  Introduced automatic E2E test triggers before each release to catch issues

## v1.2.41
- clear `fe_refresh` cookie on logout 

## v1.2.40
- Updated README.md
- Clear `frontegg.com` while logout;
- Do not post identity/resources/auth/v1/logout if refreshToken is null
- Updated README.md

## v1.2.39
FR-20294 - Reset login completion when deep link triggered

## v1.2.38
- Updated docs.
- Fixed opening external urls
- Support deep linking for redirect in Embedded Login WebView

## v1.2.37
-Added `step-up` instruction.
- Fixed `step-up` callback

## v1.2.36
- Fixed step-up
- updated demo projects
- added application-id project

# v1.2.35
- Added automation of generation CHANGELOG.md
- made `DefaultLoader`.`customLoaderView` public for flutter capability
