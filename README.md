
# Digital Shop iOS

SwiftUI customer application for a digital products store.

## Features

- Customer login and registration
- Product catalog
- Order history and review status
- Payment screenshot submission
- Secure token storage in iOS Keychain
- GitHub Actions simulator build

## Backend

The app uses the Lovable API configured in `DigitalShop/APIClient.swift`.

The backend must implement the API routes used by the app, including authentication, products, orders, and multipart payment-proof upload.

## Build

Open `DigitalShop.xcodeproj` in Xcode.

GitHub Actions builds the app for the iOS Simulator. This workflow does not create a signed IPA.
