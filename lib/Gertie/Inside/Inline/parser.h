#include <vector>
using namespace std;

class Parser {
public:
  // constructor, destructor
  Parser (int symbols);
  ~Parser();
  // builder methods
  void add_rule (int lhs_sym, int rhs1_sym, int rhs2_sym, double rule_prob);
  void set_p_empty (int sym, double p);
  void set_p_nonempty (int sym, double p);
  void init_matrix();
  // accessors
  int len();
  double get_p(int i,int j,int sym);
  double get_q(int i,int sym);
  // push/pop
  void push_tok(int tok);
  int pop_tok();
private:
  int symbols;
  vector<Rule> rule;
  vector<double> p_empty, p_nonempty;
  vector<CellPtr> cell;
  vector<int> tokseq;
};
