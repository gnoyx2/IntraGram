// 개인정보 처리 방침 (설정 › 앱 › 개인정보 처리 방침, PRIVACY.md와 같은 문구)
const Map<String, String> kStringsEnPrivacy = {
  'privacy.title': 'Privacy policy',
  'privacy.noServerTitle': 'No server, no account',
  'privacy.noServerBody':
      'IntraGram sends nothing to the developer or to any cloud service, and '
      'it needs no sign-up, phone number or email address.',
  'privacy.onDeviceTitle': 'What stays on this device',
  'privacy.onDeviceBody':
      'Messages, transfer records and keys live in memory and are gone when '
      'you quit the app or use Panic wipe. Two things are written to disk: '
      'files you accept, and the vault if you turn it on in Settings (one '
      'file in the app folder, optionally sealed with a PIN). On a computer '
      'the app also keeps a list of the folders you saved files to, so it '
      'can delete pieces of a download cut off by a crash. Panic wipe erases '
      "the vault and that list, and removing the app removes the app's "
      'folder.',
  'privacy.networkTitle': 'What leaves this device',
  'privacy.networkBody':
      'What you send goes only to the devices you connect to on this local '
      'network. App-to-app 1:1 chats are end-to-end encrypted. In a group '
      'room the host can read everything, and browser guests are not '
      'encrypted on the Wi-Fi.',
  'privacy.discoveryTitle': 'Being found',
  'privacy.discoveryBody':
      'So that nearby devices can find it, the app announces your display '
      'name, platform and port on the local network (mDNS). Anyone on the '
      'same network can see them.',
  'privacy.permissionsTitle': 'Permissions',
  'privacy.permissionsBody':
      'Local network: to find and talk to nearby devices. Microphone: only '
      'while you record a voice message. Camera: only to scan connection and '
      'security codes; no photos are kept. Notifications: new messages while '
      'the app is in the background. Photos: only the ones you pick.',
  'privacy.thirdPartyTitle': 'Third parties',
  'privacy.thirdPartyBody':
      'No third party receives data from IntraGram. QR codes are read on the '
      'device by open-source code that has no network component.',
  'privacy.contactTitle': 'Questions',
  'privacy.contactBody':
      "Open an issue on the project's GitHub page. Report security problems "
      'privately as described in SECURITY.md.',
};
