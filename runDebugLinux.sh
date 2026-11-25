#!/bin/bash
cd app
GDK_BACKEND=x11 flutter run -d linux --dart-define-from-file=oauth.defines.json --debug