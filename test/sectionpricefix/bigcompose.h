// bigcompose.h — R2-L2' priced-stub gate fixture (forsectioncollapsecheck.sh "PRICED" arms).
//
// Standalone corpus (like test/hasafix, test/legofix): BigIface has enough implementors, and enough HAS-A
// field owners, that BOTH the <lego> and <compose> sections a --for="…implementors…" query renders exceed
// the round-2 threshold — len(section) > len(stub) + len(kForSectionStubLegend) — and so still collapse to
// a counted stub by default. test/hasafix's two-field fixture is the opposite fixture on purpose: its
// <compose> is deliberately SMALL, to prove a section smaller than its own stub stays WHOLE.

class BigIface
{
public:
    virtual ~BigIface() = default;
    virtual void handleAlpha( int value ) = 0;
    virtual void handleBeta( const char* label ) = 0;
};

class AlphaImplementor : public BigIface
{
public:
    void handleAlpha( int value ) override {}
    void handleBeta( const char* label ) override {}
};

class BetaImplementor : public BigIface
{
public:
    void handleAlpha( int value ) override {}
    void handleBeta( const char* label ) override {}
};

class GammaImplementor : public BigIface
{
public:
    void handleAlpha( int value ) override {}
    void handleBeta( const char* label ) override {}
};

class DeltaImplementor : public BigIface
{
public:
    void handleAlpha( int value ) override {}
    void handleBeta( const char* label ) override {}
};

class EpsilonImplementor : public BigIface
{
public:
    void handleAlpha( int value ) override {}
    void handleBeta( const char* label ) override {}
};

// HAS-A field owners: enough distinct <field> rows that <compose> also clears the threshold.
class OwnerOne
{
private:
    AlphaImplementor m_alpha;
    BetaImplementor  m_beta;
};

class OwnerTwo
{
private:
    GammaImplementor m_gamma;
    DeltaImplementor m_delta;
};

class OwnerThree
{
private:
    EpsilonImplementor m_epsilon;
};
