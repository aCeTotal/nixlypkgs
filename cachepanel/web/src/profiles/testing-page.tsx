import { useSuspenseQuery } from "@tanstack/react-query";
import { PageHeader } from "@/shell/page-header";
import { ApproveButton } from "./approve-button";
import { BaseCard } from "./base-card";
import { DerivationsCard } from "./derivations-card";
import { approvalQuery } from "./queries";
import { StableProgress } from "./stable-progress";

export function TestingPage() {
  const { data } = useSuspenseQuery(approvalQuery);
  const waiting = data.profiles.length + data.derivations.length;
  return (
    <div className="space-y-4">
      <PageHeader
        title="Testing"
        description="Everything new lands here once it builds on every reference machine. Approve the base and each derivation on its own."
        actions={
          waiting > 0 && (
            <ApproveButton
              request={data}
              label="Approve everything"
              title="Move all of testing to stable?"
              description="Stable becomes exactly what testing runs."
            />
          )
        }
      />
      <StableProgress checks={data.stable} />
      <BaseCard approval={data} />
      <DerivationsCard derivations={data.derivations} />
    </div>
  );
}
