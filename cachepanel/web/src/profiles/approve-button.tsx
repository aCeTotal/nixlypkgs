import { useMutation } from "@tanstack/react-query";
import { CircleCheck } from "lucide-react";
import { toast } from "sonner";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/ui/alert-dialog";
import { Button } from "@/ui/button";
import { approve, type ApprovalRequest } from "./queries";

type ApproveButtonProps = {
  request: ApprovalRequest;
  label: string;
  title: string;
  description: string;
};

export function ApproveButton({ request, label, title, description }: ApproveButtonProps) {
  const ship = useMutation({ mutationFn: () => approve(request), onSuccess: () => toast.success("Approved for stable") });
  return (
    <AlertDialog>
      <AlertDialogTrigger asChild>
        <Button disabled={ship.isPending}>
          <CircleCheck />
          {label}
        </Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{title}</AlertDialogTitle>
          <AlertDialogDescription>{description}</AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>Cancel</AlertDialogCancel>
          <AlertDialogAction onClick={() => ship.mutate()}>{label}</AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
