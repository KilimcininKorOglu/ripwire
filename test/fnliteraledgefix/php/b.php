<?php
// A same-named METHOD of an unrelated class in the same directory: a bare call can never reach it.
class Other { public function php_helper($y) { return $y; } }
function other_user() { $o = new Other(); return $o->php_helper(3); }
