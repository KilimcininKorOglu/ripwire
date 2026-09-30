<?php
// PHP declares a nested named function GLOBALLY once setup() has run: use_helper's bare call means THIS php_helper.
function setup() {
    function php_helper($x) { return $x + 1; }
}
setup();
function use_helper() { return php_helper(2); }
