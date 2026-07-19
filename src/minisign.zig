const std = @import("std");
const Ed25519 = std.crypto.sign.Ed25519;

pub fn verifyMinisign(
    sig_content: []const u8,
    digest: *const [64]u8,
    filename: []const u8,
    pubkey_b64: []const u8,
) !void {
    const decoder = std.base64.standard.Decoder;

    const pubkey_len = decoder.calcSizeForSlice(pubkey_b64) catch return error.InvalidPublicKey;
    if (pubkey_len != 42) return error.InvalidPublicKey;
    var pubkey_bytes: [42]u8 = undefined;
    decoder.decode(&pubkey_bytes, pubkey_b64) catch return error.InvalidPublicKey;
    const pubkey = Ed25519.PublicKey.fromBytes(pubkey_bytes[10..42].*) catch return error.InvalidPublicKey;

    var lines = std.mem.splitSequence(u8, sig_content, "\n");

    var line1 = lines.next() orelse return error.InvalidMinisignFormat;
    if (std.mem.endsWith(u8, line1, "\r")) line1 = line1[0 .. line1.len - 1];
    if (!std.mem.startsWith(u8, line1, "untrusted comment:")) return error.InvalidMinisignFormat;

    var line2 = lines.next() orelse return error.InvalidMinisignFormat;
    if (std.mem.endsWith(u8, line2, "\r")) line2 = line2[0 .. line2.len - 1];
    const sig_blob_len = decoder.calcSizeForSlice(line2) catch return error.InvalidMinisignFormat;
    if (sig_blob_len != 74) return error.SignatureVerificationFailed;
    var sig_bytes: [74]u8 = undefined;
    decoder.decode(&sig_bytes, line2) catch return error.InvalidMinisignFormat;

    const alg = sig_bytes[0..2];
    if (!std.mem.eql(u8, alg, "ED")) return error.UnsupportedMinisignAlgorithm;
    const sig_raw = sig_bytes[10..74];

    var line3 = lines.next() orelse return error.InvalidMinisignFormat;
    if (std.mem.endsWith(u8, line3, "\r")) line3 = line3[0 .. line3.len - 1];
    if (!std.mem.startsWith(u8, line3, "trusted comment:")) return error.InvalidMinisignFormat;

    const comment_text = blk: {
        const prefix = "trusted comment: ";
        if (std.mem.startsWith(u8, line3, prefix)) break :blk line3[prefix.len..];
        break :blk line3["trusted comment:".len..];
    };

    const file_matched = blk: {
        if (std.mem.indexOf(u8, comment_text, "file:")) |idx| {
            var rest = comment_text[idx + "file:".len ..];
            rest = std.mem.trim(u8, rest, " \t");
            const end = std.mem.indexOfAny(u8, rest, " \t\r\n") orelse rest.len;
            break :blk std.mem.eql(u8, rest[0..end], filename);
        }
        break :blk false;
    };
    if (!file_matched) return error.MinisignFilenameMismatch;

    const signature = Ed25519.Signature.fromBytes(sig_raw.*);
    signature.verify(digest, pubkey) catch return error.SignatureVerificationFailed;
}
