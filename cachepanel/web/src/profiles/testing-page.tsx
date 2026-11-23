import { PageHeader } from "@/shell/page-header";
import { ApprovalCard } from "./approval-card";

export function TestingPage() {
  return (
    <div className="space-y-4">
      <PageHeader
        title="Testing"
        description="Everything new lands here once it builds on every reference machine. Approve it and it goes straight to stable."
      />
      <ApprovalCard />
    </div>
  );
}
