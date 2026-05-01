// ============================================
// Gap Fill Method (NEW)
// ============================================

pub(all) enum FillMethod {
  Null
  Previous
  Next
  Linear
  Constant(@core.Value)
} derive(Show)

