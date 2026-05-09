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
      ai_configs: {
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
      milestones: {
        Row: {
          created_at: string
          focus_objective: string | null
          id: string
          milestone_index: number
          name: string
          plan_id: string
          progress_percentage: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          focus_objective?: string | null
          id?: string
          milestone_index: number
          name: string
          plan_id: string
          progress_percentage?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          focus_objective?: string | null
          id?: string
          milestone_index?: number
          name?: string
          plan_id?: string
          progress_percentage?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "milestones_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "plans"
            referencedColumns: ["id"]
          },
        ]
      }
      plans: {
        Row: {
          answers: Json | null
          created_at: string
          domain: string | null
          expert_advice: Json
          id: string
          original_prompt: string | null
          progress_percentage: number
          prompt_available_time: string | null
          prompt_constraints: string | null
          prompt_current_status: string | null
          prompt_goal: string
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
          domain?: string | null
          expert_advice?: Json
          id?: string
          original_prompt?: string | null
          progress_percentage?: number
          prompt_available_time?: string | null
          prompt_constraints?: string | null
          prompt_current_status?: string | null
          prompt_goal: string
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
          domain?: string | null
          expert_advice?: Json
          id?: string
          original_prompt?: string | null
          progress_percentage?: number
          prompt_available_time?: string | null
          prompt_constraints?: string | null
          prompt_current_status?: string | null
          prompt_goal?: string
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
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
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
      tasks: {
        Row: {
          completed_at: string | null
          created_at: string
          details: string | null
          duration_minutes: number | null
          id: string
          milestone_id: string
          name: string
          resources_or_location: string | null
          status: Database["public"]["Enums"]["task_status"]
          task_index: number
          task_time: string | null
          updated_at: string
        }
        Insert: {
          completed_at?: string | null
          created_at?: string
          details?: string | null
          duration_minutes?: number | null
          id?: string
          milestone_id: string
          name: string
          resources_or_location?: string | null
          status?: Database["public"]["Enums"]["task_status"]
          task_index: number
          task_time?: string | null
          updated_at?: string
        }
        Update: {
          completed_at?: string | null
          created_at?: string
          details?: string | null
          duration_minutes?: number | null
          id?: string
          milestone_id?: string
          name?: string
          resources_or_location?: string | null
          status?: Database["public"]["Enums"]["task_status"]
          task_index?: number
          task_time?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tasks_milestone_id_fkey"
            columns: ["milestone_id"]
            isOneToOne: false
            referencedRelation: "milestones"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      save_plan_transaction: { Args: { payload: Json }; Returns: string }
    }
    Enums: {
      plan_status: "active" | "completed" | "abandoned"
      task_status: "pending" | "in_progress" | "completed" | "missed"
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
      plan_status: ["active", "completed", "abandoned"],
      task_status: ["pending", "in_progress", "completed", "missed"],
      tier_type: ["free", "pro"],
    },
  },
} as const
