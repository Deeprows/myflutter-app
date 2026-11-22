import '../services/subscription_service.dart';

/// Server-issued Decoder number. The Worker binds it to the account's active
/// Premium expiry and replaces it after the previous code has expired.
class DecoderNumber {
  DecoderNumber._();

  static String format(String n) =>
      n.length == 10 ? '${n.substring(0, 3)} ${n.substring(3, 6)} ${n.substring(6)}' : n;

  static Future<String?> get() =>
      SubscriptionService.instance.issueDecoderNumber();
}
