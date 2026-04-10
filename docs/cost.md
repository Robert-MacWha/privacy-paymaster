# Cost

Because the 4337 unshield flow involves double-validation of the proof (once in the paymaster, once in the privacy protocol) and has extra 4337 overhead, it is significantly more expensive than the regular unshield flow. In general it'll cost ~1.5-2x as much, depending on the protocol.

Important note: this only applies to single unshield operations. If the user adds any tail calls, those calls will be executed as-is and so won't contribute to excess costs.  For example - a tornadocash operation which unshields 5 notes would have a cost increase of only 1.1x because only the first unshield is double-validated. However, most everyday users likely won't see this benefit.

| Protocol     | Regular Unshield | 4337 Unshield (test_happyPath) | Cost Increase |
| ------------ | ---------------- | ------------------------------ | ------------- |
| Tornado Cash | 406k             | 703k                           | 1.7x          |
