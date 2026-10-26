/// A league invitation carried by the address the app was opened with: the
/// links players share (`?league=<code>`) open the web build, which reads
/// them once signed in.
library;

/// The invitation in an address; null when there is none.
typedef LaunchInvite = ({String? league});

final RegExp _code = RegExp(r'^[A-Z0-9]{6,16}$');

String? _codeIn(Uri address, String name) {
  final String? raw = address.queryParameters[name]?.trim().toUpperCase();
  return raw != null && _code.hasMatch(raw) ? raw : null;
}

/// The league code [address] carries; a malformed code is ignored.
LaunchInvite launchInviteFrom(Uri address) =>
    (league: _codeIn(address, 'league'));
