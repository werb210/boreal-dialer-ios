#!/usr/bin/env bash
# BOREAL_DIALER_v593 - Siri text, Spotlight, Focus filter and texting a shared file stay wired.
set -euo pipefail
grep -q "AppShortcut(intent: TextBorealClientIntent()" Sources/DeepLink/DeepLinkCoordinator.swift
grep -q "try await requestConfirmation" Sources/DeepLink/TextClientIntent.swift
grep -q "ContactSpotlight.index(contacts)" UI/Contacts/ContactsView.swift
grep -q "ContactSpotlight.clear()" Sources/Auth/AuthService.swift
grep -q "onContinueUserActivity(CSSearchableItemActionType)" Sources/BorealDialer/BorealDialerApp.swift
grep -q "struct BorealSiloFocusFilter: SetFocusFilterIntent" Sources/DeepLink/SiloFocusFilter.swift
grep -q "await textFile(to: contact)" UI/Documents/AttachDocumentSheet.swift
echo "v593 wiring ok"
