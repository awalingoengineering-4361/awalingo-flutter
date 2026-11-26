-- Apply before releasing the mobile build that calls this function.
BEGIN;

CREATE OR REPLACE FUNCTION public.complete_community_onboarding(p_language_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  owner_id uuid := auth.uid();
  display_name text;
BEGIN
  -- Derive the owner from Auth and serialize retries for this account.
  SELECT coalesce(
    nullif(trim(u.raw_user_meta_data->>'name'), ''),
    nullif(trim(u.raw_user_meta_data->>'display_name'), ''),
    nullif(trim(u.raw_user_meta_data->>'full_name'), ''),
    split_part(u.email, '@', 1)
  ) INTO display_name
  FROM auth.users u WHERE u.id = owner_id FOR UPDATE;

  IF NOT FOUND OR public.account_is_active() IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'An active account is required' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT FROM public.user_target_languages WHERE "userId" = owner_id
  ) THEN
    IF NOT EXISTS (
      SELECT FROM public.languages
      WHERE id = p_language_id AND is_supported AND (icon = 'NG' OR type = 'LRL')
    ) THEN
      RAISE EXCEPTION 'Choose an available community' USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.user_profile ("userId", name)
    VALUES (owner_id, display_name)
    ON CONFLICT ("userId") DO NOTHING;

    INSERT INTO public.user_target_languages ("userId", "languageId")
    VALUES (owner_id, p_language_id)
    ON CONFLICT ("userId", "languageId") DO NOTHING;
  END IF;

  UPDATE public.user_profile SET "onboardingCompleted" = true
  WHERE "userId" = owner_id AND NOT "onboardingCompleted";
END;
$$;

REVOKE ALL ON FUNCTION public.complete_community_onboarding(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_community_onboarding(integer) TO authenticated;

COMMIT;
