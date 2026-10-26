const kStringsEnAudit = <String, String>{
  'audit.title': 'Audit & Merkle Proofs',
  'audit.scope':
      'RAM only: up to 512 receipts and 64 batches. No message body. Panic wipe clears this evidence. Cleanup statements cover app-managed resources.',
  'audit.seal': 'Commit Merkle batch',
  'audit.exchange': 'Export / verify external anchor bundle',
  'audit.empty': 'No signed receipts yet. Receive a file or burn a message.',
  'audit.batch': 'Merkle batch {n} · {count} receipts',
  'audit.anchorReady': 'External anchor bundle ready · no witness verified',
  'audit.anchored': 'External anchor verified',
  'audit.copyBundle': 'Copy JSON audit bundle',
  'audit.signedReceipt': 'Signed receipt confirmed',
  'audit.signature': 'Receipt signature confirmed',
  'audit.inBatch': 'Included in Merkle batch',
  'audit.delivery': 'Delivery committed',
  'audit.burn': 'Burn policy triggered',
  'audit.cleanup': 'App resource cleanup completed',
  'audit.cleanupFailed': 'Cleanup failed / unconfirmed',
  'audit.rejected': 'Receipt rejected',
  'audit.proofMaterial': 'Merkle proof · random salt + sibling path',
  'audit.verifyProof': 'Verify signature & Merkle proof',
  'audit.copyProof': 'Copy individual proof bundle',
  'audit.valid': 'Signature and Merkle proof verified',
  'audit.invalid': 'Verification failed',
  'audit.bundleValid':
      'Bundle signatures and proofs verified · external witness unconfirmed',
  'audit.offlineFlow':
      "1. Copy the audit bundle on device A. 2. Paste on device B, verify, then sign as witness. 3. Paste the witness receipt on A and enter B's independently confirmed peer ID. A signature observes a root; it does not establish consensus or physical erasure.",
  'audit.localPeer': "This device's peer ID: {id}",
  'audit.witnessPin': 'Independently confirmed witness peer ID',
  'audit.paste': 'Paste audit bundle or witness receipt JSON',
  'audit.verifyBundle': 'Verify audit bundle',
  'audit.witness': 'Sign external root & copy receipt',
  'audit.attach': 'Verify & attach witness receipt',
  'audit.witnessCopied':
      'Witness receipt signed and copied. Return it to the requester.',
  'audit.witnessConflict':
      'Conflicting roots observed for the same requester and batch number. Witness receipt copied; investigate the conflict.',
};
