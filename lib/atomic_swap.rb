require "atomic_swap/version"

module AtomicSwap

  def self.generate_tx1_and_tx2(network, private_key_wif, recipient_pubkey_hex, amount, previous_outputs)
    Bitcoin.network = network

    # A picks a random number x
    x = SecureRandom.random_bytes(32)

    x_hash_hex = Digest::SHA256.digest(Digest::SHA256.digest(x)).unpack("H*")[0]

    # A creates TX1: "Pay w BTC to <B's public key> if (x for H(x) known and signed by B) or (signed by A & B)"
    tx1, swap_script = generate_swap_tx(private_key_wif,
                                        recipient_pubkey_hex,
                                        amount,
                                        previous_outputs,
                                        x_hash_hex)

    # A creates TX2: "Pay w BTC from TX1 to <A's public key>, locked 48 hours in the future"
    tx2 = generate_refund_tx(private_key_wif, amount, tx1, swap_script, hours=48)

    { tx1: tx1, swap_script: swap_script, x: x.unpack("H*")[0], tx2: tx2 }
  end

  def self.generate_tx3_and_tx4(network, private_key_wif, recipient_pubkey_hex, x_hash_hex, amount, previous_outputs)
    Bitcoin.network = network

    # B creates TX3: "Pay v alt-coins to <A-public-key> if (x for H(x) known and signed by A) or (signed by A & B)"
    tx3, swap_script = generate_swap_tx(private_key_wif,
                                        recipient_pubkey_hex,
                                        amount,
                                        previous_outputs,
                                        x_hash_hex)

    # B creates TX4: "Pay v alt-coins from TX3 to <B's public key>, locked 24 hours in the future"
    tx4 = generate_refund_tx(private_key_wif, amount, tx3, swap_script, hours=24)

    { tx3: tx3, swap_script: swap_script, tx4: tx4 }
  end

  FEE = (10**8)*0.0001

  def self.generate_swap_tx(private_key_wif, recipient_pubkey_hex, amount, previous_outputs, x_hash_hex)
    key = Bitcoin::Key.from_base58(private_key_wif)
    tx = Bitcoin::P::Tx.new

    # create the special swap script. it's now legit to have non-standard p2sh scripts although not all
    # nodes have upgraded yet to permit it.
    redeem_script =
      Bitcoin::Script.from_string("OP_IF" +
                                  " 2 #{key.pub} #{recipient_pubkey_hex} 2 OP_CHECKMULTISIGVERIFY " +
                                  "OP_ELSE" +
                                  " #{recipient_pubkey_hex} OP_CHECKSIGVERIFY OP_HASH256 #{x_hash_hex} OP_EQUALVERIFY").raw

    p2sh_script = Bitcoin::Script.to_p2sh_script(Bitcoin.hash160(redeem_script.unpack("H*")[0]))
    tx.add_out(Bitcoin::P::TxOut.new(amount, p2sh_script)) # tack on fee for the refund

    # add the inputs
    total = 0
    previous_outputs.each do |prev_out|
      prev_tx, prev_out_index = prev_out[:tx], prev_out[:index]
      total += prev_tx.out[prev_out_index].value
      tx.add_in(Bitcoin::P::TxIn.new(prev_tx.binary_hash, prev_out_index))
      break if total >= amount + FEE
    end
    amount *= (10**8)
    change = total - amount - FEE
    raise "insufficient funds" if change < 0
    tx.add_out(change, Bitcoin::Script.to_address_script(key.addr)) if change > 0

    # sign the inputs
    tx.in.each_with_index do |input, index|
      prev_out = previous_outputs[index]
      prev_tx, prev_out_index = prev_out[:tx], prev_out[:index]
      sighash = tx.signature_hash_for_input(index, prev_tx.out[prev_out_index].pk_script)
      tx.in[index].script_sig = Bitcoin::Script.to_signature_pubkey_script(key.sign(sighash), [key.pub].pack("H*"))
      raise "signature failure" unless tx.verify_input_signature(index, prev_tx)
    end

    [ Bitcoin::P::Tx.new(tx.to_payload), redeem_script ]
  end

  def self.generate_refund_tx(private_key_wif, amount, swap_tx, swap_script, hours)
    key = Bitcoin::Key.from_base58(private_key_wif)

    refund_tx = Bitcoin::P::Tx.new
    refund_tx.add_in(Bitcoin::P::TxIn.new(swap_tx.binary_hash, 0, script_sig='', script_sig_size=0, sequence=0))
    refund_tx.add_out(amount - FEE, Bitcoin::Script.to_address_script(key.addr))
    refund_tx.lock_time = Time.at(Time.now.to_i + hours*60*60)

    # partially sign it
    sighash = refund_tx.signature_hash_for_input(0, swap_script)
    refund_tx.in[0].script_sig = Bitcoin::Script.from_string("0 #{key.sign(sighash).unpack('H*')[0]}")

    Bitcoin::P::Tx.new(refund_tx.to_payload)
  end

  def self.sign_refund_tx(network, private_key_wif, refund_tx, swap_script)
    Bitcoin.network, key = network, Bitcoin::Key.from_base58(private_key_wif)

    # finish signing it
    sighash = refund_tx.signature_hash_for_input(0, swap_script)
    script = Bitcoin::Script.new(refund_tx.in[0].script_sig)

    # full scriptsig is "0 <sig1> <sig2> 1"
    refund_tx.in[0].script_sig =
      Bitcoin::Script.from_string("#{script.to_string} #{key.sign(sighash).unpack('H*')[0]} 1")

    Bitcoin::P::Tx.new(refund_tx.to_payload)
  end

  def self.generate_claim_tx
    # XXX TODO
  end

end
