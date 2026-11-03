/** A privileged checkout must fail closed if it cannot check the deletion queue. */
export async function checkAccountDeletion(
  lookup: () => PromiseLike<{ data: unknown; error: unknown }>,
): Promise<'active' | 'deleting' | 'unavailable'> {
  try {
    const { data, error } = await lookup();
    if (error) return 'unavailable';
    return data ? 'deleting' : 'active';
  } catch {
    return 'unavailable';
  }
}
