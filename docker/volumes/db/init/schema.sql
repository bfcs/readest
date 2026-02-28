ALTER FUNCTION auth.uid() OWNER TO supabase_auth_admin;
ALTER FUNCTION auth.role() OWNER TO supabase_auth_admin;

CREATE TABLE public.books (
  user_id uuid NOT NULL,
  book_hash text NOT NULL,
  meta_hash text NULL,
  format text NULL,
  title text NULL,
  source_title text NULL,
  author text NULL,
  "group" text NULL,
  tags text[] NULL,
  created_at timestamp with time zone NULL DEFAULT now(),
  updated_at timestamp with time zone NULL DEFAULT now(),
  deleted_at timestamp with time zone NULL,
  uploaded_at timestamp with time zone NULL,
  progress integer[] NULL,
  reading_status text NULL,
  group_id text NULL,
  group_name text NULL,
  metadata json NULL,
  CONSTRAINT books_pkey PRIMARY KEY (user_id, book_hash),
  CONSTRAINT books_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users (id) ON DELETE CASCADE
);

ALTER TABLE public.books ENABLE ROW LEVEL SECURITY;
CREATE POLICY select_books ON public.books FOR SELECT TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY insert_books ON public.books FOR INSERT TO authenticated WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY update_books ON public.books FOR UPDATE TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY delete_books ON public.books FOR DELETE TO authenticated USING ((SELECT auth.uid()) = user_id);

CREATE TABLE public.book_configs (
  user_id uuid NOT NULL,
  book_hash text NOT NULL,
  meta_hash text NULL,
  location text NULL,
  xpointer text NULL,
  progress jsonb NULL,
  search_config jsonb NULL,
  view_settings jsonb NULL,
  created_at timestamp with time zone NULL DEFAULT now(),
  updated_at timestamp with time zone NULL DEFAULT now(),
  deleted_at timestamp with time zone NULL,
  CONSTRAINT book_configs_pkey PRIMARY KEY (user_id, book_hash),
  CONSTRAINT book_configs_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users (id) ON DELETE CASCADE
);

ALTER TABLE public.book_configs ENABLE ROW LEVEL SECURITY;
CREATE POLICY select_book_configs ON public.book_configs FOR SELECT TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY insert_book_configs ON public.book_configs FOR INSERT TO authenticated WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY update_book_configs ON public.book_configs FOR UPDATE TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY delete_book_configs ON public.book_configs FOR DELETE TO authenticated USING ((SELECT auth.uid()) = user_id);

CREATE TABLE public.book_notes (
  user_id uuid NOT NULL,
  book_hash text NOT NULL,
  meta_hash text NULL,
  id text NOT NULL,
  type text NULL,
  cfi text NULL,
  text text NULL,
  style text NULL,
  color text NULL,
  note text NULL,
  page integer NULL,
  created_at timestamp with time zone NULL DEFAULT now(),
  updated_at timestamp with time zone NULL DEFAULT now(),
  deleted_at timestamp with time zone NULL,
  CONSTRAINT book_notes_pkey PRIMARY KEY (user_id, book_hash, id),
  CONSTRAINT book_notes_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users (id) ON DELETE CASCADE
);

ALTER TABLE public.book_notes ENABLE ROW LEVEL SECURITY;
CREATE POLICY select_book_notes ON public.book_notes FOR SELECT TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY insert_book_notes ON public.book_notes FOR INSERT TO authenticated WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY update_book_notes ON public.book_notes FOR UPDATE TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY delete_book_notes ON public.book_notes FOR DELETE TO authenticated USING ((SELECT auth.uid()) = user_id);

CREATE TABLE public.files (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  book_hash text NULL,
  file_key text NOT NULL,
  file_size bigint NOT NULL,
  created_at timestamp with time zone NULL DEFAULT now(),
  updated_at timestamp with time zone NULL DEFAULT now(),
  deleted_at timestamp with time zone NULL,
  CONSTRAINT files_pkey PRIMARY KEY (id),
  CONSTRAINT files_file_key_key UNIQUE (file_key),
  CONSTRAINT files_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users (id) ON DELETE CASCADE
);

CREATE INDEX idx_files_user_id_deleted_at ON public.files (user_id, deleted_at);
CREATE INDEX idx_files_file_key ON public.files (file_key);
CREATE INDEX idx_files_file_key_deleted_at ON public.files (file_key, deleted_at);

ALTER TABLE public.files ENABLE ROW LEVEL SECURITY;
CREATE POLICY files_insert ON public.files FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY files_select ON public.files FOR SELECT USING (auth.uid() = user_id AND deleted_at IS NULL);
CREATE POLICY files_update ON public.files FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (deleted_at IS NULL OR deleted_at > now());
CREATE POLICY files_delete ON public.files FOR DELETE USING (auth.uid() = user_id);

-- usage_stats table for translation quotas
CREATE TABLE public.usage_stats (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  usage_type text NOT NULL,
  usage_date date DEFAULT CURRENT_DATE NOT NULL,
  period text DEFAULT 'daily' NOT NULL,
  count bigint DEFAULT 0 NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE UNIQUE INDEX idx_usage_stats_unique ON public.usage_stats (user_id, usage_type, usage_date);

ALTER TABLE public.usage_stats ENABLE ROW LEVEL SECURITY;
CREATE POLICY select_usage_stats ON public.usage_stats FOR SELECT TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY insert_usage_stats ON public.usage_stats FOR INSERT TO authenticated WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY update_usage_stats ON public.usage_stats FOR UPDATE TO authenticated USING ((SELECT auth.uid()) = user_id);

-- Functions
CREATE OR REPLACE FUNCTION public.get_storage_by_book_hash(p_user_id uuid)
RETURNS TABLE (
  book_hash text,
  total_size bigint,
  file_count bigint
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    f.book_hash,
    SUM(f.file_size)::bigint,
    COUNT(*)::bigint
  FROM public.files f
  WHERE f.user_id = p_user_id AND f.deleted_at IS NULL
  GROUP BY f.book_hash;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_storage_stats(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_total_size bigint;
  v_file_count int;
BEGIN
  SELECT COALESCE(SUM(file_size), 0), COUNT(*)
  INTO v_total_size, v_file_count
  FROM public.files
  WHERE user_id = p_user_id AND deleted_at IS NULL;

  RETURN jsonb_build_object(
    'total_size', v_total_size,
    'file_count', v_file_count
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.increment_daily_usage(
  p_user_id uuid,
  p_usage_type text,
  p_usage_date date,
  p_increment bigint,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS bigint 
LANGUAGE plpgsql 
SECURITY DEFINER 
AS $$
DECLARE 
  v_new_count bigint;
BEGIN
  INSERT INTO public.usage_stats (user_id, usage_type, usage_date, count, metadata)
  VALUES (p_user_id, p_usage_type, p_usage_date, p_increment, p_metadata)
  ON CONFLICT (user_id, usage_type, usage_date) 
  DO UPDATE SET 
    count = usage_stats.count + p_increment, 
    metadata = usage_stats.metadata || p_metadata, 
    updated_at = now()
  RETURNING count INTO v_new_count;
  RETURN v_new_count;
END; 
$$;

CREATE OR REPLACE FUNCTION public.get_current_usage(
  p_user_id uuid,
  p_usage_type text,
  p_period text DEFAULT 'daily'
)
RETURNS bigint 
LANGUAGE plpgsql 
SECURITY DEFINER 
AS $$
DECLARE 
  v_total bigint;
BEGIN
  IF p_period = 'daily' THEN 
    SELECT COALESCE(SUM(count), 0) INTO v_total 
    FROM public.usage_stats 
    WHERE user_id = p_user_id AND usage_type = p_usage_type AND usage_date = CURRENT_DATE;
  ELSIF p_period = 'monthly' THEN 
    SELECT COALESCE(SUM(count), 0) INTO v_total 
    FROM public.usage_stats 
    WHERE user_id = p_user_id AND usage_type = p_usage_type AND usage_date >= date_trunc('month', CURRENT_DATE)::date;
  ELSE 
    v_total := 0; 
  END IF;
  RETURN v_total;
END; 
$$;

-- Grants
GRANT ALL ON public.books TO authenticated;
GRANT ALL ON public.book_configs TO authenticated;
GRANT ALL ON public.book_notes TO authenticated;
GRANT ALL ON public.files TO authenticated;
GRANT ALL ON public.usage_stats TO authenticated;
GRANT ALL ON public.usage_stats TO service_role;

GRANT EXECUTE ON FUNCTION public.get_storage_by_book_hash TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_storage_stats TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_current_usage TO authenticated;
GRANT EXECUTE ON FUNCTION public.increment_daily_usage TO authenticated;
