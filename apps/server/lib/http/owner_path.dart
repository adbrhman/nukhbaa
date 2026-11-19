/// Whether [path] is under `/owner`, the owners' page (script 287).
bool isOwnerPath(String path) => path == '/owner' || path.startsWith('/owner/');
