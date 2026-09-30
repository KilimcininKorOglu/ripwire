// A plain top-level C++ function: its name sits in a function_declarator INSIDE its own function_definition, which is
// the definition itself, never a function enclosing it.
int helper( int v ) { return v + 1; }
int use_helper() { return helper( 2 ); }
