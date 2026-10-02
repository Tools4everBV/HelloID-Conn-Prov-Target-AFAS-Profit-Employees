# Change Log

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com), and this project adheres to [Semantic Versioning](https://semver.org).

## [4.0.0] - 2026-10-02

### Changed

- Changed authentication method to OAuth client credentials (breaking: `Token` configuration field replaced by `Client ID` (`ClientId`) and `Client Secret` (`ClientSecret`))

## [3.3.3] - 2026-10-02

### Changed

- Updated the delete script to not throw an error when the person is already deleted.

## [3.3.2] - 2025-10-20

### Fixed

- Fixed `delete.ps1` audit log message wording for the "no AFAS employee found" case

## [3.3.1] - 2025-09-17

### Fixed

- Fixed `import.ps1` script

## [3.3.0] - 2025-08-11

### Added

- Added `import.ps1` for importing existing AFAS Profit employee accounts into HelloID

### Changed

- Updated README with inconsistency fixes

## [3.2.0] - 2025-06-30

### Changed

- Updated README.md

## [3.1.2] - 2025-06-30

### Changed

- Updated README.md

## [3.1.1] - 2024-12-23

### Fixed

- Fixed no error being raised when the employee is not found
- Fixed a typo in `create.ps1`

### Changed

- Updated README.md

## [3.1.0] - 2024-06-24

### Added

- Added field mapping and README documentation for the PowerShell V2 connector

### Changed

- Updated `create.ps1`

## [3.0.0] - 2024-01-11

### Changed

- Rewrote the connector as a new PowerShell V2 connector
- Updated `create.ps1`, `delete.ps1`, and `update.ps1` to the PowerShell V2 pattern
- Updated README.md and configuration.json

### Added

- Added Icon.png, Logo.png, and EmAd mapping script

## [2.1.0] - 2023-12-05

### Added

- Added required fields check and refactored the account object
- Added badges and description to README.md

### Changed

- Updated GetConnectors to Profit 1 versions
- Updated connection settings and connector fields
- Updated logging to be clearer

## [2.0.0] - 2023-10-10

### Added

- Initial tagged release
