/// The models a picker offers: [available], plus [inUse] if it is not among
/// them.
///
/// A saved model can be missing from a freshly fetched list — filtered out,
/// deprecated, or on another tier. The chat's picker then showed the first
/// model in the list as if it were the one answering, and Settings showed none
/// at all, while requests kept going to the saved one.
List<String> modelChoices(List<String> available, String? inUse) => [
  if (inUse != null && inUse.isNotEmpty && !available.contains(inUse)) inUse,
  ...available,
];
