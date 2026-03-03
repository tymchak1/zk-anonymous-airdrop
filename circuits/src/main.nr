use poseidon::poseidon2::Poseidon2;
mod merkle_tree;

fn main(
    // public
    root: pub Field,
    nullifier_hash: pub Field,
    amount: pub Field,
    recipient: pub Field,
    // private
    nullifier_secret: Field,
    eligible_address: Field,
    merkle_proof: [Field; 20],
    is_even: [bool; 20],
) {
    let leaf = Poseidon2::hash([nullifier_secret, eligible_address, amount], 3);

    let computed_nullifier = Poseidon2::hash([nullifier_secret], 1);
    assert(computed_nullifier == nullifier_hash);

    let computed_root = merkle_tree::compute_merkle_root(leaf, merkle_proof, is_even);
    assert(computed_root == root);
}
