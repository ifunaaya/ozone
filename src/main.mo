import Principal "mo:base/Principal";

import HashMap "mo:base/HashMap";
import Buffer "mo:base/Buffer";
import Int "mo:base/Int";
import Error "mo:base/Error";
import Text "mo:base/Text";
import ExperimentalCycles "mo:base/ExperimentalCycles";

import Dip721 "./DIP721";
import ICRC "./ICRC"

shared ({ caller }) actor class Main(_ckBTCPrincipal : Principal, free_NFTCanister : Principal) = this {

  type Collection = {
    principal : Principal;
    owner : {
      owner : Principal;
      subaccount : ?Blob;
    };
    allowlist : HashMap.HashMap<Principal, Bool>;
    mint_price : Nat;
  };

  type TxError = Text;
  let admin : Principal = caller;
  let ckBTC : ICRC.Token = actor (Principal.toText(_ckBTCPrincipal));

  // free NFT
  let free_NFT : Dip721.Dip721NFT = actor (Principal.toText(free_NFTCanister));
  let all_COLLECTIONS = Buffer.Buffer<Collection>(3);
  let creator_COLLECTIONS = HashMap.HashMap<Principal, Buffer.Buffer<Collection>>(1, Principal.equal, Principal.hash);

  //returns the entire collection of a creator
  private func _getCreatorCollections(creator : Principal) : Buffer.Buffer<Collection> {
    return (
      switch (creator_COLLECTIONS.get(creator)) {
        case (?collection) { collection };
        case (_) { Buffer.Buffer<Collection>(1) };
      }
    );
  };

  private func getCollectionID(collection : Collection) : Int {
    var counter : Int = -1;
    label looping for (any in all_COLLECTIONS.vals()) {

      if (collection.principal == any.principal) {
        return counter + 1;
        break looping;
      };
      counter += 1;
    };
    return counter;
  };

  private func _createCollection(caller : Principal, subaccount : ?Blob, _collectionCanister : Principal, name : Text, symbol : Text, maxLimit : Nat16, mintPrice : Nat) : async Nat {

    let new_art_canister : Dip721.Dip721NFT = actor (Principal.toText(_collectionCanister));

    let creator_collections = switch (creator_COLLECTIONS.get(caller)) {
      case (?collection) { collection };
      case (_) { Buffer.Buffer<Collection>(1) };
    };

    // make a new collection
    let new_collection : Collection = {
      principal = Principal.fromActor(new_art_canister);
      owner = { owner = caller; subaccount = subaccount };
      allowlist = HashMap.HashMap<Principal, Bool>(1, Principal.equal, Principal.hash);
      mint_price = mintPrice;
    };

    creator_collections.add(new_collection);

    all_COLLECTIONS.add(new_collection);

    creator_COLLECTIONS.put(caller, creator_collections);
    return all_COLLECTIONS.size();

  };

  public shared ({ caller }) func createCollection(subaccount : ?Blob, collectionCanister : Principal, name : Text, symbol : Text, maxLimit : Nat16, mintPrice : Nat) : async {
    collectionID : Nat;
  } {
    return {
      collectionID = await _createCollection(caller, subaccount, collectionCanister, name, symbol, maxLimit, mintPrice);
    };
  };

  //whitelist users so thry can mint your collection ,
  //can only be called by tthe coollection owner
  public shared ({ caller }) func whiteListUser(user : Principal, collectionID : Nat) : async Text {
    let collection = all_COLLECTIONS.get(collectionID);
    if (caller != collection.owner.owner) {
      return "Only collection owners can whitelist user";
    };
    collection.allowlist.put(user, true);
    return "Succesfully !user can now mint your art";
  };

  //Mints a free NFT

  public shared ({ caller }) func freeMint() : async Text {
    let new_NFT = await free_NFT.mintDip721(caller, [{ purpose = #Preview; key_val_data = [{ key = Principal.toText(caller); val = #TextContent("Ozone brings back ownership to creators") }]; data = Principal.toBlob(caller) }]);

    let nft_details = switch (new_NFT) {
      case (#Ok(details)) { details };
      case (#Err(err)) { return "You are not Eligible to Mint this" };
    };

    return "Minted for free! say hello to true ownership ";
  };

  //mints an NFT from a collection by paying the mint_price amount in ckBTC
  public shared ({ caller }) func mintCreatorCollection(collectionID : Nat, subaccount : ?Blob) : async TxError {
    let collection : Collection = all_COLLECTIONS.get(collectionID);

    let isAllowed = switch (collection.allowlist.get(caller)) {
      case (?res) { res };
      case (_) { false };
    };
    if (not isAllowed) {
      return "You are not permitted to mint this NFT";
    };
    let fee = await ckBTC.icrc1_fee();
    let payment = await ckBTC.icrc2_transfer_from({
      amount = collection.mint_price;
      created_at_time = null;
      fee = ?fee;
      memo = null;
      from = { owner = caller; subaccount = subaccount };
      spender_subaccount = null;
      to = collection.owner;
    });
    let isValid = switch (payment) {
      case (#Ok(res)) { true };
      case (#Err(err)) {
        return "No payment received ,ensure you have enought ckBTC to proceed";
      };
    };
    let collection_canister : Dip721.Dip721NFT = actor (Principal.toText(collection.principal));
    let mintTx = await collection_canister.mintDip721(caller, [{ purpose = #Preview; key_val_data = [{ key = Principal.toText(caller); val = #TextContent("Ozone brings back ownership to creators") }]; data = Principal.toBlob(caller) }]);
    switch (mintTx) {
      case (#Ok(res)) { return "Succesfully" };
      case (#Err(res)) { return "There was an Error in Minting this" };
    };
  };

};