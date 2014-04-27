#!/bin/sh
ARGS="--watch ../members-area"
for I in ../members-area-*; do
  ARGS="$ARGS --watch $I";
done
./node_modules/.bin/nodemon --ignore node_modules/ --ignore public/ --ignore db/ --ignore views/ --ignore app/views/ --ignore app/db/ --ignore scripts/ --ignore sessions/ --ignore log/ $ARGS --watch . index.coffee
