/// The web keeps no crest file: each is drawn from its URL (script 266).
library;

import 'crest_shelf.dart';

/// The shelf of the web.
CrestShelf? platformCrestShelf() => const UrlCrestShelf();
