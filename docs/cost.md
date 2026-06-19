# Cost

Cost depends heavily on the protocol being used and whether fee refunds are possible.  In general, 4337 relaying will be at least 100k gas more expensive than a raw transaction due to entrypoint overhead.

### Tornadocash

- Regular unshield: ~400k gas
- Native-relayed unshield: ~400k gas + ~0.1% fee
- 4337-relayed unshield: ~500k gas

*Tornadocash is currently the only protocol that supports fee refunds, which makes relayed unshields very cost-effective. Furthermore, tornadocash's native relayer network tend to charge very high fees.*

### Railgun

- Regular unshield (unshield + change note): ~1,200 gas
- Waku-relayed unshield: ~1,200 gas + 100k gas fee + ~0.1% gas fee 
- 4337-relayed unshield: ~1,800 gas

*Railgun does not currently support fee refunds (cost of performing a shielded fee refund would be ~900k gas + operational complexity). This means the bundler & paymaster safety margins can't be refunded after a successful operation.*
