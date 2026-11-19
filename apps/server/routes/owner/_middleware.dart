import 'package:dart_frog/dart_frog.dart';
import 'package:server/http/owner_gate.dart';

/// Guards the whole `/owner` subtree (script 287): an owner seat reaches
/// its routes; anyone else gets the answer of a path with no route
/// ([ownerGate]).
// NK287_04
Handler middleware(Handler handler) {
  return handler.use(ownerGate());
}
