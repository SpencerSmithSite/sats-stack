/// Where wallet history is read from.
///
/// Bitcoin Core is not one: it keeps no index of addresses, so it cannot list
/// an address's history. `BitcoinNodeService` stays for connection testing
/// and, later, broadcasting.
enum BitcoinDataSource {
  /// A Mempool/Esplora HTTP API — mempool.space unless the user set their own.
  mempool,

  /// The user's own Electrum server (electrs, Fulcrum), over TCP or TLS.
  electrum,
}
