export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      ai_config: {
        Row: {
          created_at: string
          id: string
          max_output_tokens: number
          model_name: string
          tier: Database["public"]["Enums"]["tier_type"]
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          max_output_tokens: number
          model_name: string
          tier: Database["public"]["Enums"]["tier_type"]
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          max_output_tokens?: number
          model_name?: string
          tier?: Database["public"]["Enums"]["tier_type"]
          updated_at?: string
        }
        Relationships: []
      }
      calendar_sync_connection: {
        Row: {
          account_email: string | null
          created_at: string
          enabled: boolean
          id: string
          last_error: string | null
          last_synced_at: string | null
          provider: string
          provider_calendar_id: string | null
          provider_calendar_name: string | null
          sync_cursor: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          account_email?: string | null
          created_at?: string
          enabled?: boolean
          id?: string
          last_error?: string | null
          last_synced_at?: string | null
          provider: string
          provider_calendar_id?: string | null
          provider_calendar_name?: string | null
          sync_cursor?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          account_email?: string | null
          created_at?: string
          enabled?: boolean
          id?: string
          last_error?: string | null
          last_synced_at?: string | null
          provider?: string
          provider_calendar_id?: string | null
          provider_calendar_name?: string | null
          sync_cursor?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      calendar_sync_event: {
        Row: {
          created_at: string
          id: string
          provider: string
          provider_calendar_id: string | null
          provider_deleted: boolean
          provider_event_id: string
          provider_updated_at: string | null
          task_id: string
          task_updated_at: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          provider: string
          provider_calendar_id?: string | null
          provider_deleted?: boolean
          provider_event_id: string
          provider_updated_at?: string | null
          task_id: string
          task_updated_at?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          provider?: string
          provider_calendar_id?: string | null
          provider_deleted?: boolean
          provider_event_id?: string
          provider_updated_at?: string | null
          task_id?: string
          task_updated_at?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "calendar_sync_event_task_id_fkey"
            columns: ["task_id"]
            isOneToOne: false
            referencedRelation: "daily_task"
            referencedColumns: ["id"]
          },
        ]
      }
      calendar_sync_token: {
        Row: {
          access_token_encrypted: string
          created_at: string
          expires_at: string | null
          id: string
          provider: string
          refresh_token_encrypted: string | null
          scopes: string[]
          token_type: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          access_token_encrypted: string
          created_at?: string
          expires_at?: string | null
          id?: string
          provider: string
          refresh_token_encrypted?: string | null
          scopes?: string[]
          token_type?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          access_token_encrypted?: string
          created_at?: string
          expires_at?: string | null
          id?: string
          provider?: string
          refresh_token_encrypted?: string | null
          scopes?: string[]
          token_type?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      daily_task: {
        Row: {
          calendar_event_id: string | null
          color: string | null
          completed_at: string | null
          created_at: string
          deleted_at: string | null
          deleted_by_device_id: string | null
          details: string | null
          duration_minutes: number | null
          id: string
          milestone_id: string | null
          name: string
          priority: Database["public"]["Enums"]["task_priority"]
          reminders_json: string | null
          resources_or_location: string | null
          rrule: string | null
          scheduled_end: string | null
          scheduled_start: string
          status: Database["public"]["Enums"]["task_status"]
          task_index: number
          task_type: Database["public"]["Enums"]["task_type_enum"]
          updated_at: string
          user_id: string | null
        }
        Insert: {
          calendar_event_id?: string | null
          color?: string | null
          completed_at?: string | null
          created_at?: string
          deleted_at?: string | null
          deleted_by_device_id?: string | null
          details?: string | null
          duration_minutes?: number | null
          id?: string
          milestone_id?: string | null
          name: string
          priority?: Database["public"]["Enums"]["task_priority"]
          reminders_json?: string | null
          resources_or_location?: string | null
          rrule?: string | null
          scheduled_end?: string | null
          scheduled_start: string
          status?: Database["public"]["Enums"]["task_status"]
          task_index?: number
          task_type?: Database["public"]["Enums"]["task_type_enum"]
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          calendar_event_id?: string | null
          color?: string | null
          completed_at?: string | null
          created_at?: string
          deleted_at?: string | null
          deleted_by_device_id?: string | null
          details?: string | null
          duration_minutes?: number | null
          id?: string
          milestone_id?: string | null
          name?: string
          priority?: Database["public"]["Enums"]["task_priority"]
          reminders_json?: string | null
          resources_or_location?: string | null
          rrule?: string | null
          scheduled_end?: string | null
          scheduled_start?: string
          status?: Database["public"]["Enums"]["task_status"]
          task_index?: number
          task_type?: Database["public"]["Enums"]["task_type_enum"]
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tasks_milestone_id_fkey"
            columns: ["milestone_id"]
            isOneToOne: false
            referencedRelation: "milestone"
            referencedColumns: ["id"]
          },
        ]
      }
      milestone: {
        Row: {
          created_at: string
          deleted_at: string | null
          deleted_by_device_id: string | null
          end_date: string | null
          focus_objective: string | null
          id: string
          milestone_index: number
          name: string
          plan_id: string
          progress_percentage: number
          start_date: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          deleted_by_device_id?: string | null
          end_date?: string | null
          focus_objective?: string | null
          id?: string
          milestone_index: number
          name: string
          plan_id: string
          progress_percentage?: number
          start_date?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          deleted_at?: string | null
          deleted_by_device_id?: string | null
          end_date?: string | null
          focus_objective?: string | null
          id?: string
          milestone_index?: number
          name?: string
          plan_id?: string
          progress_percentage?: number
          start_date?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "milestones_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "plan"
            referencedColumns: ["id"]
          },
        ]
      }
      note: {
        Row: {
          content_delta: Json
          created_at: string
          deleted_at: string | null
          deleted_by_device_id: string | null
          id: string
          plain_text: string
          reference_id: string | null
          reference_type:
            | Database["public"]["Enums"]["note_reference_type_enum"]
            | null
          scheduled_at: string | null
          title: string
          updated_at: string
          user_id: string
        }
        Insert: {
          content_delta?: Json
          created_at?: string
          deleted_at?: string | null
          deleted_by_device_id?: string | null
          id?: string
          plain_text?: string
          reference_id?: string | null
          reference_type?:
            | Database["public"]["Enums"]["note_reference_type_enum"]
            | null
          scheduled_at?: string | null
          title?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          content_delta?: Json
          created_at?: string
          deleted_at?: string | null
          deleted_by_device_id?: string | null
          id?: string
          plain_text?: string
          reference_id?: string | null
          reference_type?:
            | Database["public"]["Enums"]["note_reference_type_enum"]
            | null
          scheduled_at?: string | null
          title?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      plan: {
        Row: {
          answers: Json | null
          created_at: string
          deleted_at: string | null
          deleted_by_device_id: string | null
          domain: string | null
          end_date: string | null
          expert_advice: Json
          id: string
          original_prompt: string | null
          progress_percentage: number
          prompt_available_time: string | null
          prompt_constraints: string | null
          prompt_current_status: string | null
          prompt_goal: string
          start_date: string | null
          status: Database["public"]["Enums"]["plan_status"]
          success_metrics: Json
          title: string
          total_duration: string | null
          ultimate_goal: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          answers?: Json | null
          created_at?: string
          deleted_at?: string | null
          deleted_by_device_id?: string | null
          domain?: string | null
          end_date?: string | null
          expert_advice?: Json
          id?: string
          original_prompt?: string | null
          progress_percentage?: number
          prompt_available_time?: string | null
          prompt_constraints?: string | null
          prompt_current_status?: string | null
          prompt_goal: string
          start_date?: string | null
          status?: Database["public"]["Enums"]["plan_status"]
          success_metrics?: Json
          title: string
          total_duration?: string | null
          ultimate_goal?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          answers?: Json | null
          created_at?: string
          deleted_at?: string | null
          deleted_by_device_id?: string | null
          domain?: string | null
          end_date?: string | null
          expert_advice?: Json
          id?: string
          original_prompt?: string | null
          progress_percentage?: number
          prompt_available_time?: string | null
          prompt_constraints?: string | null
          prompt_current_status?: string | null
          prompt_goal?: string
          start_date?: string | null
          status?: Database["public"]["Enums"]["plan_status"]
          success_metrics?: Json
          title?: string
          total_duration?: string | null
          ultimate_goal?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "plans_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profile"
            referencedColumns: ["id"]
          },
        ]
      }
      profile: {
        Row: {
          avatar_url: string | null
          created_at: string
          email: string | null
          full_name: string | null
          id: string
          locale: string
          theme_mode: number
          tier: Database["public"]["Enums"]["tier_type"]
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string
          email?: string | null
          full_name?: string | null
          id: string
          locale?: string
          theme_mode?: number
          tier?: Database["public"]["Enums"]["tier_type"]
        }
        Update: {
          avatar_url?: string | null
          created_at?: string
          email?: string | null
          full_name?: string | null
          id?: string
          locale?: string
          theme_mode?: number
          tier?: Database["public"]["Enums"]["tier_type"]
        }
        Relationships: []
      }
      user_device: {
        Row: {
          created_at: string
          device_id: string
          id: string
          last_synced_at: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          device_id: string
          id?: string
          last_synced_at?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          device_id?: string
          id?: string
          last_synced_at?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      get_plan_detail: { Args: { p_plan_id: string }; Returns: Json }
      get_sync_changes: { Args: { p_last_synced_at?: string }; Returns: Json }
      set_user_device_synced: {
        Args: { p_device_id: string; p_last_synced_at: string }
        Returns: {
          created_at: string
          device_id: string
          id: string
          last_synced_at: string | null
          updated_at: string
          user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "user_device"
          isOneToOne: true
          isSetofReturn: false
        }
      }
    }
    Enums: {
      note_reference_type_enum: "plan" | "milestone" | "task"
      plan_status: "active" | "completed" | "abandoned"
      task_priority: "low" | "medium" | "high" | "critical"
      task_status: "pending" | "in_progress" | "completed" | "missed"
      task_type_enum:
        | "ai_plan"
        | "manual_single"
        | "manual_routine"
        | "reminder"
      tier_type: "free" | "pro"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      note_reference_type_enum: ["plan", "milestone", "task"],
      plan_status: ["active", "completed", "abandoned"],
      task_priority: ["low", "medium", "high", "critical"],
      task_status: ["pending", "in_progress", "completed", "missed"],
      task_type_enum: [
        "ai_plan",
        "manual_single",
        "manual_routine",
        "reminder",
      ],
      tier_type: ["free", "pro"],
    },
  },
} as const
